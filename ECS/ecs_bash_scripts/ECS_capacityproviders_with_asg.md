REGION=ap-southeast-2

# 1) AMI from SSM
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id \
  --region "$REGION" --query 'Parameter.Value' --output text)

# 2) Create Launch Configuration (uses instance profile NAME; adjust if yours differs)
aws autoscaling create-launch-configuration \
  --launch-configuration-name MyLaunchConfig2 \
  --image-id "$AMI_ID" \
  --instance-type t3.medium \
  --iam-instance-profile ecsInstanceProfile \
  --key-name RemoteLinuxKey \
  --security-groups sg-0f93c256f9a64cf21 \
  --user-data file://user-data.sh \
  --region "$REGION"

# 3) ASG
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name MyASG2 \
  --launch-configuration-name MyLaunchConfig2 \
  --min-size 1 \
  --max-size 5 \
  --desired-capacity 1 \
  --vpc-zone-identifier "subnet-0f4a85d2a1bc7738a,subnet-0212a8ec9de45d7bc" \
  --region "$REGION"

# 4) Cluster
aws ecs create-cluster --cluster-name MyEC2Cluster2 --region "$REGION"

# 5) Capacity provider (lookup the ASG ARN dynamically)
ASG_ARN=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names MyASG2 \
  --region "$REGION" \
  --query 'AutoScalingGroups[0].AutoScalingGroupARN' --output text)

aws ecs create-capacity-provider \
  --name MyCapacityProvider2 \
  --auto-scaling-group-provider "autoScalingGroupArn=${ASG_ARN},managedScaling={status=ENABLED,minimumScalingStepSize=1,maximumScalingStepSize=10,targetCapacity=100},managedTerminationProtection=DISABLED" \
  --region "$REGION"

aws ecs put-cluster-capacity-providers \
  --cluster MyEC2Cluster2 \
  --capacity-providers MyCapacityProvider2 \
  --default-capacity-provider-strategy "capacityProvider=MyCapacityProvider2,weight=1" \
  --region "$REGION"

# 6) Task def + service (ensure network mode matches your task def)
aws ecs register-task-definition --cli-input-json file://task-definition-ec2.json --region "$REGION"

# Example for a BRIDGE/HOST task definition (no awsvpc networking flag):
aws ecs create-service \
  --cluster MyEC2Cluster2 \
  --service-name MyEC2Service2 \
  --placement-strategy type=binpack,field=memory type=spread,field=attribute:ecs.availability-zone \
  --task-definition my-ec2-task \
  --desired-count 1 \
  --capacity-provider-strategy "capacityProvider=MyCapacityProvider2,weight=1" \
  --region "$REGION"

# If your task uses awsvpc, add:
#   --network-configuration "awsvpcConfiguration={subnets=[subnet-...],securityGroups=[sg-...],assignPublicIp=DISABLED}"

# 7) Update termination protection (must include the ARN again)
aws ecs update-capacity-provider \
  --name MyCapacityProvider2 \
  --auto-scaling-group-provider "autoScalingGroupArn=${ASG_ARN},managedTerminationProtection=DISABLED" \
  --region "$REGION"

aws ecs update-capacity-provider \
  --name MyCapacityProvider2 \
  --auto-scaling-group-provider "autoScalingGroupArn=${ASG_ARN},managedTerminationProtection=ENABLED" \
  --region "$REGION"


# Delete service
aws ecs delete-service --cluster MyEC2Cluster2 --service MyEC2Service2 --force --region "$REGION"

# Detach capacity providers from cluster 
aws ecs put-cluster-capacity-providers \
  --cluster MyEC2Cluster2 \
  --capacity-providers [] \
  --region "$REGION"

# Delete capacity provider
aws ecs delete-capacity-provider --capacity-provider MyCapacityProvider2 --region "$REGION"

# Delete cluster
aws ecs delete-cluster --cluster MyEC2Cluster2 --region "$REGION"

# Delete ASG + launch config
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name MyASG2 --force-delete --region "$REGION"
aws autoscaling delete-launch-configuration --launch-configuration-name MyLaunchConfig2 --region "$REGION"
