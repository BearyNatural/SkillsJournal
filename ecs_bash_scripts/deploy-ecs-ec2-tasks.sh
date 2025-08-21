# make it executable and then execute it
    # chmod +x deploy-ecs-ec2-tasks.sh
    # ./deploy-ecs-ec2-tasks.sh

# A simple hello-world app with a sleep of 2 mins

#!/bin/bash
set -e
set -x

CLUSTER_NAME="ecs-ec2-cluster"
REGION="ap-southeast-2"
VPC_CIDR="10.0.0.0/16"
AZS=(${REGION}a ${REGION}b ${REGION}c)

TASK_DEF_NAME="hello-world-task"
SERVICE_NAME="hello-world-service"
CONTAINER_NAME="hello-container"
IMAGE="amazonlinux"
INSTANCE_TYPE="t3.small"
LAUNCH_TEMPLATE_NAME="ECSLaunchTemplate"
ASG_NAME="ECSAutoScalingGroup"

# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --region $REGION --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="$CLUSTER_NAME" --region $REGION
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support --region $REGION
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region $REGION

# Subnets
PUBLIC_SUBNET_IDS=()
PRIVATE_SUBNET_IDS=()
for i in "${!AZS[@]}"; do
  PUB_SUBNET=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.0.$((i * 2)).0/24" --availability-zone "${AZS[$i]}" --region $REGION --query 'Subnet.SubnetId' --output text)
  aws ec2 modify-subnet-attribute --subnet-id "$PUB_SUBNET" --map-public-ip-on-launch --region $REGION

  PRIV_SUBNET=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.0.$((i * 2 + 1)).0/24" --availability-zone "${AZS[$i]}" --region $REGION --query 'Subnet.SubnetId' --output text)

  PUBLIC_SUBNET_IDS+=("$PUB_SUBNET")
  PRIVATE_SUBNET_IDS+=("$PRIV_SUBNET")
done

PUBLIC_SUBNETS=$(IFS=, ; echo "${PUBLIC_SUBNET_IDS[*]}")
PRIVATE_SUBNETS=$(IFS=, ; echo "${PRIVATE_SUBNET_IDS[*]}")

# Internet Gateway and Public Route Table
IGW_ID=$(aws ec2 create-internet-gateway --region $REGION --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region $REGION

PUB_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region $REGION --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PUB_RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region $REGION
for s in "${PUBLIC_SUBNET_IDS[@]}"; do
  aws ec2 associate-route-table --subnet-id "$s" --route-table-id "$PUB_RT_ID" --region $REGION
  done

# NAT Gateway for Private Subnets
EIP_ALLOC=$(aws ec2 allocate-address --region $REGION --domain vpc --query 'AllocationId' --output text)
NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id "${PUBLIC_SUBNET_IDS[0]}" --allocation-id "$EIP_ALLOC" --region $REGION --query 'NatGateway.NatGatewayId' --output text)
echo "Waiting for NAT Gateway to become available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GW_ID" --region $REGION

PRIV_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region $REGION --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PRIV_RT_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GW_ID" --region $REGION
for s in "${PRIVATE_SUBNET_IDS[@]}"; do
  aws ec2 associate-route-table --subnet-id "$s" --route-table-id "$PRIV_RT_ID" --region $REGION
  done

# ECS Cluster
aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region $REGION

# Security Groups
SG_ECS=$(aws ec2 create-security-group --group-name ECSInstanceSG --description "ECS EC2 access" --vpc-id "$VPC_ID" --region $REGION --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ECS" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION

SG_APP=$(aws ec2 create-security-group --group-name AppSG --description "App access" --vpc-id "$VPC_ID" --region $REGION --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_APP" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION

# Launch Template and Auto Scaling Group
AMI_ID=$(aws ssm get-parameter --name /aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id --region $REGION --query 'Parameter.Value' --output text)
PROFILE_ARN=$(aws iam get-instance-profile --instance-profile-name ecsInstanceProfile --query 'InstanceProfile.Arn' --output text)
USER_DATA=$(echo -n "#!/bin/bash
echo ECS_CLUSTER=$CLUSTER_NAME >> /etc/ecs/ecs.config" | base64)

LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
  --region $REGION \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --version-description "ECS launch template" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"$INSTANCE_TYPE\",
    \"IamInstanceProfile\": {\"Arn\": \"$PROFILE_ARN\"},
    \"SecurityGroupIds\": [\"$SG_ECS\"],
    \"UserData\": \"$USER_DATA\"
  }" --query 'LaunchTemplate.LaunchTemplateId' --output text)

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateId=$LAUNCH_TEMPLATE_ID,Version=1" \
  --min-size 1 --max-size 3 --desired-capacity 1 \
  --vpc-zone-identifier "$PUBLIC_SUBNETS" \
  --region $REGION

# Create hello-task.json script
cat > hello-task.json <<EOF
[
  {
    "name": "hello-container",
    "image": "amazonlinux",
    "entryPoint": ["/bin/sh", "-c"],
    "command": ["echo Hello ECS && sleep 120"],
    "essential": true,
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80,
        "protocol": "tcp"
      }
    ]
  }
]
EOF

echo "Task Definition Script created"

# Task Definition
aws ecs register-task-definition \
  --family "$TASK_DEF_NAME" \
  --requires-compatibilities EC2 \
  --network-mode awsvpc \
  --cpu "256" \
  --memory "512" \
  --region $REGION \
  --container-definitions file://hello-task.json \
  --output text

echo "Task Definition created"

# ECS Service
aws ecs create-service \
  --cluster "$CLUSTER_NAME" \
  --service-name "$SERVICE_NAME" \
  --task-definition "$TASK_DEF_NAME" \
  --launch-type EC2 \
  --desired-count 1 \
  --network-configuration "awsvpcConfiguration={subnets=[${PRIVATE_SUBNET_IDS[0]}],securityGroups=[$SG_APP],assignPublicIp=DISABLED}" \
  --region $REGION \
  --output text

echo "ECS deployment completed with cluster: $CLUSTER_NAME, service: $SERVICE_NAME"



# checking

# aws ecs create-service \
#   --region ap-southeast-2 \
#   --cluster ecs-ec2-cluster \
#   --service-name hello-world-service \
#   --task-definition hello-world-task \
#   --launch-type EC2 \
#   --desired-count 1 \
#   --network-configuration "awsvpcConfiguration={subnets=[subnet-04e095bdd0f8c8ba3],securityGroups=[sg-0b06435b6e2a8def4],assignPublicIp=DISABLED}" \
#   --region ap-southeast-2

# aws ecs list-container-instances --cluster ecs-ec2-cluster --region ap-southeast-2

# aws ec2 describe-instances \
#   --filters "Name=tag:Name,Values=ECSLaunchTemplate" "Name=instance-state-name,Values=running" \
#   --region ap-southeast-2 \
#   --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,AZ:Placement.AvailabilityZone}"

# aws ecs describe-container-instances \
#   --cluster ecs-ec2-cluster \
#   --container-instances <container-instance-id> \
#   --region ap-southeast-2
