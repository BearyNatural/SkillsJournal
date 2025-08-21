#!/bin/bash
set -e

CLUSTER_NAME="eks-al2023-test"
REGION="ap-southeast-2"
NODEGROUP_NAME="al2023-ng"
INSTANCE_TYPE="m5.xlarge"
MAX_NODES=3
MIN_NODES=1
K8S_VERSION="1.32"  

# Get the latest AL2023 AMI ID
AL2023_AMI=$(aws ssm get-parameter \
  --name "/aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2023/x86_64/standard/recommended/image_id" \
  --region "$REGION" \
  --query "Parameter.Value" \
  --output text)

echo "AL2023 AMI: $AL2023_AMI"

# Generate base64-encoded bootstrap user data
USER_DATA=$(base64 -w 0 <<EOF
#!/bin/bash
/etc/eks/bootstrap.sh ${CLUSTER_NAME} \
--kubelet-extra-args '--system-reserved=cpu=250m,memory=1Gi \
--kube-reserved=cpu=250m,memory=1Gi \
--eviction-hard=memory.available<500Mi'
EOF
)

LT_NAME="${CLUSTER_NAME}-launch-template"
aws ec2 create-launch-template \
  --launch-template-name "$LT_NAME" \
  --version-description "AL2023-EKS" \
  --launch-template-data "{
    \"ImageId\": \"$AL2023_AMI\",
    \"InstanceType\": \"$INSTANCE_TYPE\",
    \"UserData\": \"$USER_DATA\"
  }" \
  --region "$REGION"

LT_ID=$(aws ec2 describe-launch-templates \
  --launch-template-names "$LT_NAME" \
  --region "$REGION" \
  --query "LaunchTemplates[0].LaunchTemplateId" \
  --output text)

echo "Launch Template ID: $LT_ID"

# Write compatible eksctl config YAML
cat <<EOF > eks-cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: $CLUSTER_NAME
  region: $REGION
  version: "$K8S_VERSION"

managedNodeGroups:
  - name: $NODEGROUP_NAME
    desiredCapacity: $MIN_NODES
    minSize: $MIN_NODES
    maxSize: $MAX_NODES
    launchTemplate:
      id: $LT_ID
    iam:
      withAddonPolicies:
        autoScaler: true
        cloudWatch: true
        ebs: true
EOF

echo "Creating EKS Cluster and Node Group..."
eksctl create cluster -f eks-cluster.yaml

echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=10m

echo "Deploying long-running test pods..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sleeper
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sleeper
  template:
    metadata:
      labels:
        app: sleeper
    spec:
      containers:
      - name: sleep
        image: busybox
        command: ["sleep", "1209600"]  # 14 days
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
EOF

echo "Cluster created, sleeper pods deployed, bootstrap script applied."
