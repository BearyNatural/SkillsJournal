#!/bin/bash
set -e

CLUSTER_NAME="eks-al2023-test"
REGION="ap-southeast-2"
LT_NAME="${CLUSTER_NAME}-launch-template"
CFN_STACK_NAME="eksctl-${CLUSTER_NAME}-cluster"

echo "Checking for EKS Cluster: $CLUSTER_NAME"
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" > /dev/null 2>&1; then
  echo "Deleting EKS Cluster: $CLUSTER_NAME"
  eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION"
else
  echo "EKS Cluster $CLUSTER_NAME not found, skipping eksctl cluster deletion."
fi

echo "Checking for CloudFormation Stack: $CFN_STACK_NAME"
STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "$CFN_STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || true)

if [[ "$STACK_STATUS" != "" && "$STACK_STATUS" != "DELETE_COMPLETE" ]]; then
  echo "Deleting CloudFormation stack: $CFN_STACK_NAME (status: $STACK_STATUS)"
  aws cloudformation delete-stack \
    --stack-name "$CFN_STACK_NAME" \
    --region "$REGION"
  echo "Waiting for stack deletion to complete..."
  aws cloudformation wait stack-delete-complete \
    --stack-name "$CFN_STACK_NAME" \
    --region "$REGION"
  echo "CloudFormation stack deleted."
else
  echo "No active CloudFormation stack found for $CFN_STACK_NAME."
fi

echo "Checking for Launch Template: $LT_NAME"
LT_ID=$(aws ec2 describe-launch-templates \
  --launch-template-names "$LT_NAME" \
  --region "$REGION" \
  --query "LaunchTemplates[0].LaunchTemplateId" \
  --output text 2>/dev/null || true)

if [ -n "$LT_ID" ] && [ "$LT_ID" != "None" ]; then
  echo "Deleting Launch Template ID: $LT_ID"
  aws ec2 delete-launch-template \
    --launch-template-id "$LT_ID" \
    --region "$REGION"
  echo "Launch template $LT_NAME deleted."
else
  echo "Launch template $LT_NAME not found or already deleted."
fi

echo "Cleaning up unassociated Elastic IPs in region: $REGION"
EIP_IDS=$(aws ec2 describe-addresses --region "$REGION" \
  --query "Addresses[?AssociationId==null].AllocationId" --output text)

if [ -z "$EIP_IDS" ]; then
  echo "No unassociated EIPs found."
else
  for eip in $EIP_IDS; do
    echo "Releasing EIP Allocation ID: $eip"
    aws ec2 release-address --allocation-id "$eip" --region "$REGION"
  done
fi

echo "Removing eks-cluster.yaml (if present)..."
rm -f eks-cluster.yaml

echo "Cleanup complete."
