# make it executable and then execute it
    # chmod +x deploy-self-managed-eks.sh
    # ./deploy-self-managed-eks.sh

#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===
CLUSTER_NAME="self-managed-eks"
REGION="ap-southeast-2"
INSTANCE_TYPE="t3.medium"

# === CREATE CLUSTER ===
echo "\n Checking for EKS cluster..."
if ! aws eks --region $REGION describe-cluster --name "$CLUSTER_NAME" &>/dev/null; then
  echo " Creating EKS control plane..."
  eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --version "1.31" \
    --region "$REGION" \
    --without-nodegroup \
    
else
  echo " EKS cluster already exists."
fi

# === FETCH VPC ID AFTER CLUSTER ===
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo " VPC ID: $VPC_ID"

# === FETCH SUBNETS FROM VPC ===
SUBNET_IDS=($(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].SubnetId" --output text || echo ""))

if [[ ${#SUBNET_IDS[@]} -eq 0 ]]; then
  echo " No subnets found in VPC $VPC_ID. Cannot proceed."
  exit 1
fi

# Split subnets by tags
PUBLIC_SUBNET_ID=""
PRIVATE_SUBNET_IDS=()

for subnet_id in "${SUBNET_IDS[@]}"; do
  ROLE=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$subnet_id" "Name=key,Values=kubernetes.io/role/elb" --query "Tags[0].Value" --output text 2>/dev/null || echo "")
  if [[ "$ROLE" == "1" ]]; then
    PUBLIC_SUBNET_ID="$subnet_id"
  else
    PRIVATE_SUBNET_IDS+=("$subnet_id")
  fi

done

if [[ -z "$PUBLIC_SUBNET_ID" || ${#PRIVATE_SUBNET_IDS[@]} -lt 1 ]]; then
  echo " Error: required subnet tags missing or not enough subnets."
  exit 1
fi

# === GET LATEST AMI ===
AMI_ID=$(aws ssm get-parameters \
  --names /aws/service/eks/optimized-ami/1.31/amazon-linux-2/recommended/image_id \
  --region $REGION --query 'Parameters[0].Value' --output text)

# === CREATE SELF-MANAGED NODEGROUP TEMPLATE ===
cat <<EOF > self-managed-nodegroup.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Self-managed node group for EKS

Parameters:
  ClusterName:
    Type: String
  NodeInstanceType:
    Type: String
  VpcId:
    Type: AWS::EC2::VPC::Id
  Subnets:
    Type: List<AWS::EC2::Subnet::Id

Resources:
  NodeInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - ec2.amazonaws.com
            Action:
              - sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

  NodeInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Roles:
        - !Ref NodeInstanceRole

  LaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateData:
        InstanceType: !Ref NodeInstanceType
        IamInstanceProfile:
          Name: !Ref NodeInstanceProfile
        UserData:
          Fn::Base64: !Sub |
            #!/bin/bash
            /etc/eks/bootstrap.sh ${ClusterName}
        TagSpecifications:
          - ResourceType: instance
            Tags:
              - Key: Name
                Value: !Sub ${ClusterName}-node
              - Key: kubernetes.io/cluster/${ClusterName}
                Value: owned

  NodeGroupASG:
    Type: AWS::AutoScaling::AutoScalingGroup
    Properties:
      VPCZoneIdentifier: !Ref Subnets
      LaunchTemplate:
        LaunchTemplateId: !Ref LaunchTemplate
        Version: !GetAtt LaunchTemplate.LatestVersionNumber
      MinSize: 1
      MaxSize: 3
      DesiredCapacity: 1
      Tags:
        - Key: Name
          Value: !Sub ${ClusterName}-asg
          PropagateAtLaunch: true
        - Key: kubernetes.io/cluster/${ClusterName}
          Value: owned
          PropagateAtLaunch: true
EOF

# === CREATE SELF-MANAGED NODEGROUP ===
echo "
  Creating self-managed node group..."
NODEGROUP_STACK_NAME="${CLUSTER_NAME}-self-managed-nodegroup"

aws cloudformation create-stack \
  --stack-name $NODEGROUP_STACK_NAME \
  --template-body file://self-managed-nodegroup.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters ParameterKey=ClusterName,ParameterValue=$CLUSTER_NAME \
               ParameterKey=NodeInstanceType,ParameterValue=$INSTANCE_TYPE \
               ParameterKey=VpcId,ParameterValue=$VPC_ID \
               ParameterKey=Subnets,ParameterValue=\"${PRIVATE_SUBNET_IDS[*]}\"

aws cloudformation wait stack-create-complete --stack-name $NODEGROUP_STACK_NAME
echo " Self-managed node group stack created."

# === LAUNCH EC2 NODE ===
echo "
 Launching EC2 instance in private subnet..."
aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --iam-instance-profile Name="AmazonEKSWorkerNodeRole" \
  --network-interfaces "DeviceIndex=0,AssociatePublicIpAddress=false,SubnetId=${PRIVATE_SUBNET_IDS[0]}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=eks:cluster-name,Value=$CLUSTER_NAME}]" \
  --user-data file://<(cat <<EOF
#!/bin/bash
/etc/eks/bootstrap.sh $CLUSTER_NAME
EOF
)

# === WAIT FOR NODE ===
echo " Waiting for node to register..."
sleep 90

# === METRICS SERVER ===
echo "\n Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# === LOAD BALANCER CONTROLLER ===
echo "\n Installing AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update
kubectl create namespace kube-system || true

helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$VPC_ID

# === DEPLOY APP ===
echo "\n Deploying sleepy app and ingress..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sleepy-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sleepy
  template:
    metadata:
      labels:
        app: sleepy
    spec:
      containers:
      - name: sleeper
        image: busybox
        command: ["/bin/sh", "-c", "sleep 600"]
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: sleepy-service
spec:
  selector:
    app: sleepy
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sleepy-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/subnets: $PUBLIC_SUBNET_ID
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sleepy-service
            port:
              number: 80
EOF

# === AUTOSCALING ===
kubectl autoscale deployment sleepy-app --cpu-percent=50 --min=1 --max=20

echo -e "\n All setup complete!"
echo "Run: kubectl get ingress sleepy-ingress"
