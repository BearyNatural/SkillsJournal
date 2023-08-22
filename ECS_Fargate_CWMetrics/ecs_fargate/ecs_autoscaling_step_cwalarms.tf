# Create an Auto Scaling service
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 3
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.lab_ecs_cluster.name}/${aws_ecs_service.lab_fargate_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Create the Scale up alarm
resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "scale-up-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2" 
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "This metric triggers the autoscaling when the CPU exceeds 75%"
  treat_missing_data = "ignore"
  datapoints_to_alarm = "2" # Out of the 2 evaluation periods, 2 must be in alarm to alarm.

  dimensions = {
    ClusterName = aws_ecs_cluster.lab_ecs_cluster.name
    ServiceName = aws_ecs_service.lab_fargate_service.name
  }

  alarm_actions = [ aws_appautoscaling_policy.scale_up_policy.arn ]
}

# Create an Auto Scaling Policy - Step tracking - Up
resource "aws_appautoscaling_policy" "scale_up_policy" {
  name               = "scale-up-policy"
  policy_type        = "StepScaling" # "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  step_scaling_policy_configuration {
    adjustment_type = "ChangeInCapacity"
    cooldown = 120
    metric_aggregation_type = "Average"
    step_adjustment {
      scaling_adjustment = 1
      metric_interval_lower_bound = 0
    }
  }

#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageCPUUtilization"
#     }
#     target_value = 75
#   }
}

# Create the Scale down alarm with metrics
resource "aws_cloudwatch_metric_alarm" "scale_down_alarm_w_metrics" {
  alarm_name          = "scale_down_alarm_w_metrics"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  threshold           = "2"
  treat_missing_data = "ignore"
  datapoints_to_alarm = "2" # Out of the 2 evaluation periods, 2 must be in alarm to alarm.

  alarm_description   = "This metric triggers the autoscaling when the CPU drops below 25% also has math metrics"

  alarm_actions = [aws_appautoscaling_policy.scale_down_policy.arn]

# m1 metric
  metric_query {
    id = "cpu_util"
    metric {
      metric_name = "CPUUtilization"
      namespace   = "AWS/ECS"
      period      = "60"
      stat        = "Average"
    
      dimensions = {
        ClusterName = aws_ecs_cluster.lab_ecs_cluster.name
        ServiceName = aws_ecs_service.lab_fargate_service.name
      }
    }
  }

# m2 metric
  metric_query {
    id = "task_count"
    metric {
      metric_name = "DesiredTaskCount"
      namespace   = "ECS/ContainerInsights"
      period      = "60"
      stat        = "Average"

      dimensions = {
        ClusterName = aws_ecs_cluster.lab_ecs_cluster.name
        ServiceName = aws_ecs_service.lab_fargate_service.name
      }
    }
  }
# e1, e2, e3 combined
  metric_query {
    id          = "final_expr"
    expression  = "IF(cpu_util < 25, 1, 0) + IF(task_count > 2, 1, 0)"
    label       = "CombinedExpr"
    return_data = true
  }
}

# Create an Auto Scaling Policy - Step tracking - Down
resource "aws_appautoscaling_policy" "scale_down_policy" {
  name               = "scale-down-policy"
  policy_type        = "StepScaling" # "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = -1
      metric_interval_upper_bound = 0
    }
  }
}


# Create the baseline Scale down alarm without metrics
resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "scale-down-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  threshold           = "25"
  metric_name         = "CPUUtilization"
  treat_missing_data  = "ignore"
  datapoints_to_alarm = "2" # Out of the 2 evaluation periods, 2 must be in alarm to alarm.
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"

  alarm_description   = "This metric triggers the autoscaling when the CPU drops below 25%"

  dimensions = {
    ClusterName = aws_ecs_cluster.lab_ecs_cluster.name
    ServiceName = aws_ecs_service.lab_fargate_service.name
  }
}
