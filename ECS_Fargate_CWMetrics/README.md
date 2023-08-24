# Proof of Concept: CloudWatch Alarms Utilizing Math Metrics to Optimize AutoScaling Efficiency!
by Kaylene Howe

  Terraform Scripted:
  In the dynamic realm of cloud infrastructure management, CloudWatch alarms play a crucial role in maintaining efficient and cost-effective operations. Recently, there was a case where a CloudWatch alarm became stuck in an alarm state, while this didn't impact the performance of an ECS cluster it was annoying to the client. 
  In this post, we delve into the issue faced by client, the underlying problem causing the alarm to stay active, and a proof-of-concept solution that involves the use of math metrics. This solution not only resolved the problem at hand but also promises to enhance auto-scaling processes. Let's dive in and explore the journey from a persistent alarm state to an optimized auto-scaling setup!

![alt text](https://github.com/BearyNatural/SkillsJournal/blob/main/ECS_Fargate_CWMetrics/CloudWatchAlarm%20metrics%20source%20code.PNG)
![alt text](https://github.com/BearyNatural/SkillsJournal/blob/main/ECS_Fargate_CWMetrics/ECS%20Autoscaling%20Cloudwatch%20Alarms%20with%20metrics.PNG)

