# Terraform:
terraform validate
terraform init
terraform plan
terraform apply
terraform apply --auto-approve
terraform destroy
terraform destroy --auto-approve

# For more information please see the documentation:
- [Terraform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- Combination of the following:
  - [ECS Autoscaling policy](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html) using [Step scaling policies](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-autoscaling-stepscaling.html)
  - [CloudWatch Alarm](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html) i.e. Scale up/down [adjustments](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-simple-step.html)
  - [Math Metric](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create-alarm-on-metric-math-expression.html) to silence the alarm when policy & alarm have done their job;
- Paying for the additional metrics, the [container insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html), and cloudwatch log data to take the alarm out of alarm state when the lower bound was reached i.e. cpu under 25% & running task count was on min as per ECS scaling policy [Pricing](https://aws.amazon.com/cloudwatch/pricing/)
