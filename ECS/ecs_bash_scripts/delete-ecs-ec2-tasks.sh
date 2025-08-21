# make it executable and then execute it
    # chmod +x delete-ecs-ec2-tasks.sh
    # ./delete-ecs-ec2-tasks.sh

#!/bin/bash
set -e

CLUSTER_NAME="ecs-ec2-cluster"
REGION="ap-southeast-2"
LAUNCH_TEMPLATE_NAME="ECSLaunchTemplate"
ASG_NAME="ECSAutoScalingGroup"
ALB_NAME="ecs-alb"

echo "Cleaning up ECS EC2 resources in $REGION..."

# Describe cluster status
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region $REGION --query "clusters[0].status" --output text 2>/dev/null || echo "")

# Delete ECS Cluster if ACTIVE
if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
  echo "Checking for ECS services in cluster: $CLUSTER_NAME"
  SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region $REGION --query "serviceArns[]" --output text)

  if [[ -n "$SERVICES" ]]; then
    echo "Deleting ECS services in cluster: $CLUSTER_NAME"
    for SERVICE in $SERVICES; do
      SERVICE_NAME=$(basename "$SERVICE")
      echo "Updating service $SERVICE_NAME to desired count 0..."
      aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --desired-count 0 --region $REGION || true
      echo "Deleting service: $SERVICE_NAME"
      aws ecs delete-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --force --region $REGION || true
    done
    echo "Waiting for services to be deleted..."
    sleep 10
  fi

  echo "Deleting ECS cluster: $CLUSTER_NAME"
  aws ecs delete-cluster --cluster "$CLUSTER_NAME" --region $REGION
else
  echo "ECS cluster is not ACTIVE or doesn't exist (status: $CLUSTER_STATUS)"
fi

# Delete Auto Scaling Group
ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups --region $REGION --query "AutoScalingGroups[?AutoScalingGroupName=='$ASG_NAME']" --output text)
if [[ -n "$ASG_EXISTS" ]]; then
  echo "Deleting Auto Scaling Group: $ASG_NAME"
  aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --min-size 0 --max-size 0 --desired-capacity 0 --region $REGION || true
  sleep 10
  aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --force-delete --region $REGION || true
else
  echo "Auto Scaling Group $ASG_NAME not found"
fi

# Delete Launch Template
LT_ID=$(aws ec2 describe-launch-templates --region $REGION --query "LaunchTemplates[?LaunchTemplateName=='$LAUNCH_TEMPLATE_NAME'].LaunchTemplateId" --output text)
if [[ -n "$LT_ID" ]]; then
  echo "Deleting Launch Template: $LAUNCH_TEMPLATE_NAME"
  aws ec2 delete-launch-template --launch-template-id "$LT_ID" --region $REGION
fi

# Delete ALB
ALB_ARN=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?LoadBalancerName=='$ALB_NAME'].LoadBalancerArn" --output text)
if [[ -n "$ALB_ARN" ]]; then
  echo "Deleting ALB: $ALB_NAME"
  LISTENER_ARNS=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region $REGION --query "Listeners[].ListenerArn" --output text)
  for L in $LISTENER_ARNS; do
    aws elbv2 delete-listener --listener-arn "$L" --region $REGION || true
  done
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region $REGION || true
  sleep 10
fi

# Delete Security Groups
SG_IDS=$(aws ec2 describe-security-groups --region $REGION --filters Name=group-name,Values="ECSInstanceSG","ALBSG" --query "SecurityGroups[].GroupId" --output text)
for SG in $SG_IDS; do
  echo "Deleting Security Group: $SG"
  aws ec2 delete-security-group --group-id "$SG" --region $REGION || echo "Could not delete SG $SG (likely still in use)"
done

# Get VPC ID by tag
VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters Name=tag:Name,Values="$CLUSTER_NAME" --query "Vpcs[0].VpcId" --output text)
if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  echo "VPC not found for tag Name=$CLUSTER_NAME"
  exit 0
else
  echo "Deleting resources in VPC: $VPC_ID"
fi

# Delete NAT Gateways
NAT_GWS=$(aws ec2 describe-nat-gateways --region $REGION --filter Name=vpc-id,Values=$VPC_ID --query "NatGateways[].NatGatewayId" --output text)
for NAT in $NAT_GWS; do
  echo "Deleting NAT Gateway: $NAT"
  aws ec2 delete-nat-gateway --nat-gateway-id $NAT --region $REGION || true
  sleep 10
done

# Detach & delete IGW
IGW_ID=$(aws ec2 describe-internet-gateways --region $REGION --filters Name=attachment.vpc-id,Values="$VPC_ID" --query "InternetGateways[0].InternetGatewayId" --output text)
if [[ "$IGW_ID" != "None" && -n "$IGW_ID" ]]; then
  echo "Detaching and deleting IGW: $IGW_ID"
  aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region $REGION || true
  aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region $REGION || true
else
  echo "No Internet Gateway found attached to VPC"
fi

# Delete all non-main route tables (main gets deleted with VPC)
ROUTE_TABLES=$(aws ec2 describe-route-tables --region $REGION --filters Name=vpc-id,Values="$VPC_ID" --query "RouteTables[].RouteTableId" --output text)
for RT_ID in $ROUTE_TABLES; do
  IS_MAIN=$(aws ec2 describe-route-tables --route-table-ids "$RT_ID" --region $REGION --query "RouteTables[0].Associations[?Main==true].Main" --output text)
  if [[ "$IS_MAIN" == "True" ]]; then
    echo "Skipping main route table: $RT_ID"
    continue
  fi

  echo "Deleting custom route table: $RT_ID"
  ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$RT_ID" --region $REGION --query "RouteTables[0].Associations[].RouteTableAssociationId" --output text)
    for AID in $ASSOC_IDS; do
    IS_MAIN_ASSOC=$(aws ec2 describe-route-tables --route-table-ids "$RT_ID" --region $REGION \
        --query "RouteTables[0].Associations[?RouteTableAssociationId=='$AID'].Main" --output text)
    if [[ "$IS_MAIN_ASSOC" == "True" ]]; then
        echo "Skipping disassociation of main route table association: $AID"
        continue
    fi
    echo "Disassociating route table association: $AID"
    aws ec2 disassociate-route-table --association-id "$AID" --region $REGION || true
    done
  aws ec2 delete-route-table --route-table-id "$RT_ID" --region $REGION || echo "Failed to delete route table $RT_ID"
done

# Delete subnets
SUBNETS=$(aws ec2 describe-subnets --region $REGION --filters Name=vpc-id,Values="$VPC_ID" --query "Subnets[].SubnetId" --output text)
for SUBNET in $SUBNETS; do
  echo "Deleting subnet: $SUBNET"
  aws ec2 delete-subnet --subnet-id "$SUBNET" --region $REGION || true
done

# Delete ENIs
ENIS=$(aws ec2 describe-network-interfaces --region $REGION --filters Name=vpc-id,Values=$VPC_ID --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
for ENI in $ENIS; do
  echo "Deleting ENI: $ENI"
  aws ec2 delete-network-interface --network-interface-id $ENI --region $REGION || echo "Failed to delete ENI $ENI"
done

# Wait to ensure resource propagation
echo "Waiting for resources to fully detach before deleting VPC..."
sleep 10

# Delete the VPC
echo "Deleting VPC: $VPC_ID"
aws ec2 delete-vpc --vpc-id "$VPC_ID" --region $REGION || echo "Could not delete VPC $VPC_ID (still has dependencies), trying to force delete"
aws ec2 delete-vpc --vpc-id "$VPC_ID" --region $REGION --force