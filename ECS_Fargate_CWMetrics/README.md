# Proof of Concept: CloudWatch Alarms Utilizing Math Metrics to Optimize AutoScaling Efficiency!
by Kaylene Howe

  Terraform Scripted:
  In the dynamic realm of cloud infrastructure management, CloudWatch alarms play a crucial role in maintaining efficient and cost-effective operations. Recently, there was a case where a CloudWatch alarm became stuck in an alarm state, while this didn't impact the performance of an ECS cluster it was annoying to the client. 
  In this post, we delve into a proof-of-concept solution that involves the use of math metrics. This solution not only resolved the problem at hand but also promises to enhance ECS AutoScaling processes. Let's dive in and explore the issue of a persistent alarm state to an optimized auto-scaling setup!

Step 1.
  Ensure you have terraform setup and the correct permissions for terraform to work.  For more information please see [Instructions](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

  Please ensure you read through the codes and the scripts.  Get familiar with everything and where each module is.  You can make changes to the code & scripts, changing the region, the desired task count on the CloudWatch Alarm (must still match the ECS AutoScaling policy, so change this also).

Step 2. 
  Open the CLI in the folder where the 'main.tf' file is.  Now we need to spin up the scipt into your AWS account.  As per terraform documentation use the following commands in order. [Commands](https://developer.hashicorp.com/terraform/cli/commands)

  terraform init
    - this will prepare your working directory for other commands;

  terraform validate
    - this will chick whether the configuration is valid;

  terraform plan
    - this will show changes required by the current configuration;

  terraform apply --auto-approve
    - this will run the plan and then create or update the infrastructure;
      If the code errors with service unavailable, this is a temporary issue that occurs when there are no available spot instances to build the image correctly.  There has however been infrastructure set up.  In this case we need to pull down the infrastructure using this command:
        terraform destroy --auto-approve
        - this will destroy previously created infrastructure
      Essentially you have a few different options.  You can try again, now or later.  Or you can change the AZ the spot instance is created in.  Under the ec2 folder, in the ec2.tf file, on line 30 is where you will find the AZ choice, change it from 'a' to 'b' or 'c'.  Please ensure the region you are spinning the script up in has the AZ.

Step 3.

![alt text](https://github.com/BearyNatural/SkillsJournal/blob/main/ECS_Fargate_CWMetrics/CloudWatchAlarm%20metrics%20source%20code.PNG)
![alt text](https://github.com/BearyNatural/SkillsJournal/blob/main/ECS_Fargate_CWMetrics/ECS%20Autoscaling%20Cloudwatch%20Alarms%20with%20metrics.PNG)


Step .
  This is the point where you get to decide which type of script you want to use for stressing the tasks.  In the containers folder there are two folders with scripts, one for powershell, the other for bash.  Make your choice and cd into the folder and follow the instructions in the README.md in the containers folder.

Step .
  terraform destroy --auto-approve
    - this will destroy previously created infrastructure