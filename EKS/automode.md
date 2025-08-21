Walkthrough

The source code for this post is available in AWS-Samples on GitHub.

git clone https://github.com/aws-samples/containers-blog-maelstrom/
cd containers-blog-maelstrom/prefetch-data-to-EKSnodes

Let’s start by setting environment variables:

export EDP_AWS_REGION=us-east-1
export EDP_AWS_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
export EDP_NAME=prefetching-data-automation

Create an Amazon EKS cluster:

envsubst < cluster-config.yaml | eksctl create cluster -f -

Create Amazon Elastic Container Registry repository to store the sample application’s image:

aws ecr create-repository \
    --cli-input-json file://repo.json  \
    --repository-name ${EDP_NAME} \
    --region $EDP_AWS_REGION

Create a large container image:

./build-docker-image.sh

Create an AWS Identity and Access Management (AWS IAM) role for Amazon EventBridge:

aws iam create-role \
    --role-name $EDP_NAME-role \
    --assume-role-policy-document file://events-trust-policy.json

Attach a policy to the role that allows Amazon EventBridge to run commands on cluster’s worker nodes using AWS Systems Manager:

aws iam put-role-policy \
    --role-name ${EDP_NAME}-role \
    --policy-name ${EDP_NAME}-policy \
    --policy-document "$(envsubst < events-policy.json)"

Create an Amazon EventBridge rule that looks for push events on the Amazon ECR repository:

envsubst < events-rule.json > events-rule-updated.json 
aws events put-rule \
  --cli-input-json file://events-rule-updated.json \
  --region $EDP_AWS_REGION
rm events-rule-updated.json

Attach System Manager Run command as the target. Whenever we push a new image to the Amazon ECR repository, Amazon EventBridge triggers SSM run command to pull the new image on worker nodes.

envsubst '$EDP_AWS_REGION $EDP_AWS_ACCOUNT $EDP_NAME' < events-target.json > events-target-updated.json
aws events put-targets --rule $EDP_NAME \
  --cli-input-json file://events-target-updated.json \
  --region $EDP_AWS_REGION
rm events-target-updated.json 

Create an AWS Systems Manager State Manager association to prefetch sample application’s images on new worker nodes:

envsubst '$EDP_AWS_REGION $EDP_AWS_ACCOUNT $EDP_NAME' < \
  statemanager-association.json > statemanager-association-updated.json 
aws ssm create-association --cli-input-json \
  file://statemanager-association-updated.json \
  --region $EDP_AWS_REGION
rm statemanager-association-updated.json

Note: The status of AWS SSM State Manager association will be in “failed” state until the first run.


eksctl delete cluster --region=us-east-1 --name=prefetching-data-automation

MIA: 
    AmazonEKSBlockStoragePolicy
    AmazonEKSComputePolicy
    AmazonEKSLoadBalancingPolicy
    AmazonEKSNetworkingPolicy

    "sts:TagSession"

aws ecr create-repository --cli-input-json file://repo.json  --repository-name ${EDP_NAME} --region $EDP_AWS_REGION

[repository:
  createdAt: '2025-02-05T07:06:07.191000+10:00'
  encryptionConfiguration:
    encryptionType: AES256
  imageScanningConfiguration:
    scanOnPush: false
  imageTagMutability: MUTABLE
  registryId: 'ACCOUNT_ID'
  repositoryArn: arn:aws:ecr:us-east-1:ACCOUNT_ID:repository/prefetching-data-automation
  repositoryName: prefetching-data-automation
  repositoryUri: ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation]

# Remove EventBridge targets & rule
aws events remove-targets --rule "$EDP_NAME" --ids "1" --region "$EDP_AWS_REGION" || true
aws events delete-rule --name "$EDP_NAME" --region "$EDP_AWS_REGION" || true

# Delete SSM association (replace with your AssociationId if you captured it)
# aws ssm list-associations --query 'Associations[].AssociationId' --output text
aws ssm delete-association --association-id "<ASSOC_ID>" --region "$EDP_AWS_REGION" || true

# Detach & delete IAM inline policy, then role
aws iam delete-role-policy --role-name "${EDP_NAME}-role" --policy-name "${EDP_NAME}-policy" || true
aws iam delete-role --role-name "${EDP_NAME}-role" || true

# Delete ECR repo (will fail if images exist—empty it first)
aws ecr delete-repository --repository-name "${EDP_NAME}" --region "$EDP_AWS_REGION" --force || true

# Delete cluster
eksctl delete cluster --region="$EDP_AWS_REGION" --name="$EDP_NAME"
