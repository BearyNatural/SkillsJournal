# make it executable and then execute it
    # chmod +x delete-self-managed-eks.sh
    # ./delete-self-managed-eks.sh

#!/bin/bash

set -e

# === CONFIGURABLE ===
CLUSTER_NAME="self-managed-eks"
REGION="ap-southeast-2"
PUBLIC_SUBNET_ID="subnet-0abc1234public"  # update
PRIVATE_SUBNET_IDS=("subnet-0def5678private1" "subnet-0ghi9012private2")  # update

# === DELETE K8S RESOURCES ===
echo "Deleting K8s resources..."
kubectl delete ingress sleepy-ingress || true
kubectl delete service sleepy-service || true
kubectl delete deployment sleepy-app || true
kubectl delete hpa sleepy-app || true
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || true

# === DELETE ALB CONTROLLER ===
helm uninstall aws-load-balancer-controller -n kube-system || true

# === TERMINATE EC2 NODES ===
echo "Terminating EC2 instances tagged with cluster..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
  --query "Reservations[*].Instances[*].InstanceId" --output text)

if [[ -n "$INSTANCE_IDS" ]]; then
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
  echo "Waiting for termination..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
else
  echo "No EC2 instances found."
fi

# === DELETE SUBNET TAGS ===
echo "Removing subnet tags..."
aws ec2 delete-tags --resources $PUBLIC_SUBNET_ID --tags Key=kubernetes.io/role/elb || true
for subnet in "${PRIVATE_SUBNET_IDS[@]}"; do
  aws ec2 delete-tags --resources $subnet --tags Key=kubernetes.io/role/internal-elb || true
done

# === DELETE EKS CLUSTER + CFN STACK ===
echo "Deleting EKS cluster and CloudFormation stack via eksctl..."
if eksctl delete cluster --name $CLUSTER_NAME --region $REGION; then
  echo "EKS cluster deleted successfully."
else
  echo "eksctl cluster deletion failed. Attempting manual CloudFormation stack deletion..."
  STACK_NAME="eksctl-${CLUSTER_NAME}-cluster"
  aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
  aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION
  echo "CloudFormation stack deleted."
fi

echo " Cleanup complete!"
