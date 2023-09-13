# Proof of Concept: CloudWatch Alarms Utilizing Math Metrics to Optimize AutoScaling Efficiency!
by :sunflower: Kaylene Howe :dancing_duck:

---

## Terraform Scripted:
In the dynamic realm of cloud infrastructure management, CloudWatch alarms play a crucial role in maintaining efficient and cost-effective operations. Recently, there was a case where a CloudWatch alarm became stuck in an alarm state, while this didn't impact the performance of an ECS cluster it was annoying to the client. 
In this post, we delve into a proof-of-concept solution that involves the use of math metrics. This solution not only resolved the problem at hand but also promises to enhance ECS AutoScaling processes. Let's dive in and explore the issue of a persistent alarm state to an optimized auto-scaling setup!

---

### Step 1.
Ensure you have terraform setup and the correct permissions for terraform to work.  For more information please see [Instructions](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

*Please ensure you read through the codes and the scripts.  Get familiar with everything and where each module is.  You can make changes to the code & scripts, changing the region, the desired task count on the CloudWatch Alarm (must still match the ECS AutoScaling policy, so change this also).*

### Step 2. 
Open the CLI in the folder where the 'main.tf' file is.  Now we need to spin up the scipt into your AWS account.  As per terraform documentation use the following commands in order. [Commands](https://developer.hashicorp.com/terraform/cli/commands)

'terraform init'
  - this will prepare your working directory for other commands;

'terraform validate'
  - this will chick whether the configuration is valid;

'terraform plan'
  - this will show changes required by the current configuration;

'terraform apply --auto-approve'
  - this will run the plan and then create or update the infrastructure; *If the code errors with service unavailable, this is a temporary issue that occurs when there are no available spot instances to build the image correctly.  There has however been infrastructure set up.  In this case we need to pull down the infrastructure using this command:*
    'terraform destroy --auto-approve'
      - this will destroy previously created infrastructure.  *Essentially you have a few different options.  You can try again after the destroy, now or later.  Or you can change the AZ the spot instance is created in.  Under the ec2 folder, in the ec2.tf file, on line 30 is where you will find the AZ choice, change it from 'a' to 'b' or 'c'.  Please ensure the region you are spinning the script up in has the AZ.*

### Step 3.
You can now see the infrastructure setup in your account.  If you can't see it, double check your region.  Ensure the Tasks are up and running and the alarms have sufficient data.  This may take a few minutes.

![alt text](https://github.com/BearyNatural/SkillsJournal/blob/main/ECS_Fargate_CWMetrics/ECS%20Autoscaling%20Cloudwatch%20Alarms%20with%20metrics.PNG)

![alt text](https://github.com/BearyNatural/SkillsJournal/blob/main/ECS_Fargate_CWMetrics/CloudWatchAlarm%20metrics%20source%20code.PNG)

*Once everything is ready move onto the next step.*

### Step 4.
This is the point where you get to decide which type of script you use for stressing the tasks.  In the containers folder there are two folders with scripts, one for powershell, the other for bash.  Make your choice and cd into the folder and follow the instructions in the README.md.
*take your time with this step, play to your hearts content*

### Step 5.
The best thing about scripts, the ease in which the infrastructure can be pulled down!!

'terraform destroy --auto-approve'
  - this will destroy previously created infrastructure


# For more information please see the documentation:
- [Terraform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- Combination of the following:
  - [ECS Autoscaling policy](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html) using [Step scaling policies](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-autoscaling-stepscaling.html)
  - [CloudWatch Alarm](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html) i.e. Scale up/down [adjustments](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-simple-step.html)
  - [Math Metric](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create-alarm-on-metric-math-expression.html) to silence the alarm when policy & alarm have done their job;
- Paying for the additional metrics, the [container insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html), and cloudwatch log data to take the alarm out of alarm state when the lower bound was reached i.e. cpu under 25% & running task count was on min as per ECS scaling policy [Pricing](https://aws.amazon.com/cloudwatch/pricing/)

# Troubleshooting when deploying script
- if you get this error:
    'Error: waiting for EC2 Spot Instance Request to be fulfilled: unexpected state 'capacity-not-available', wanted target 'fulfilled'. last error: There is no Spot capacity available that matches your request.
    with module.ec2.aws_spot_instance_request.docker_image_builder,
    on ec2\ec2.tf line 43, in resource "aws_spot_instance_request" "docker_image_builder":
    43: resource "aws_spot_instance_request" "docker_image_builder" ...'
- *The error message you're encountering indicates that there are no available EC2 Spot capacity that matches your request. This means that at the moment you tried to launch your Spot Instance, there were no spare resources available in the Spot pool that met your specified criteria.  To remedy this either change the spot instance to another az and redeploy or just redeploy.*