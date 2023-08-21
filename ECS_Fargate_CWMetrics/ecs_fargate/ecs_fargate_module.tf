# Create an ECS Fargate cluster
resource "aws_ecs_cluster" "lab_ecs_cluster"  {
  name = "lab_ecs_cluster"  
  setting {
    name = "containerInsights"
    value = "enabled"
  }
}

# Create an IAM role for the ECS Tasks
resource "aws_iam_role" "lab_ecs_execution_role" {
  name = "lab_ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole",
      },
    ],
  })
}

# Attach an IAM role for the Tasks
resource "aws_iam_role_policy_attachment" "lab_ecs_attach" {
  role = aws_iam_role.lab_ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Create an IAM role for the ECS service to publish logs to CloudWatch
resource "aws_iam_policy" "ecs_logging" {
  name        = "ECSLogging"
  description = "Allow ECS tasks to send logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = aws_cloudwatch_log_group.ecs_logs.arn
      }
    ]
  })
}

# Attach the IAM role for logging
resource "aws_iam_role_policy_attachment" "ecs_logging_attachment" {
  role       = aws_iam_role.lab_ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_logging.arn
}

# Create a task definition
resource "aws_ecs_task_definition" "lab_ecs_taskdefinition" {
  family = "lab_task_family"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.lab_ecs_execution_role.arn

  # container_definitions = <<DEFINITION
  # [
  #   {
  #     "name": "alabcontainer",
  #     "image": "'${var.repourl}':latest",
  #     "essential": true,
  #     "portMappings" = [
  #       {
  #         "containerPort" = 8080
  #       }
  #     ]
  #     "logConfiguration": {
  #       "logDriver": "awslogs",
  #       "options": {
  #         "awslogs-group": "aws_cloudwatch_log_group.ecs_logs.name",
  #         "awslogs-region": '${var.region}',
  #         "awslogs-stream-prefix": "ecs"
  #       }
  #     }
  #   }
  # ]
  # DEFINITION

  container_definitions = jsonencode([
  {
    name  = "my-container"
    image = "${var.repourl}:latest"
    portMappings = [
      {
        containerPort = 8080
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }
])
}

# Create a Fargate service
resource "aws_ecs_service" "lab_fargate_service" {
  name = "lab_fargate_service"
  cluster = aws_ecs_cluster.lab_ecs_cluster.id
  task_definition = aws_ecs_task_definition.lab_ecs_taskdefinition.arn
  launch_type = "FARGATE"
  depends_on = [ aws_security_group.lab_ecs_sg ]

  network_configuration {
    subnets = [ var.subnet1, var.subnet2 ]
    security_groups = [ aws_security_group.lab_ecs_sg.id ]
    assign_public_ip = true
  }

  desired_count = 2

  lifecycle {
    create_before_destroy = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200
}

# Create a security group for the ECS tasks
resource "aws_security_group" "lab_ecs_sg" {
  name_prefix = "lab_ecs_sg-"
  description = "Allow webaccess inbound traffic"
  vpc_id = var.vpc

  //Allow incoming traffic to the Fargate contianers
  ingress = [
    {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    ipv6_cidr_blocks = null
    prefix_list_ids = null
    security_groups = null
    self = null
    description = null
  }]
    egress = [
    {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
    ipv6_cidr_blocks = null
    prefix_list_ids = null
    security_groups = null
    self = null
    description = null
  }]
}

# Create the CloudWatch log group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name = "/ecs/lab_fargate_service"
  retention_in_days = 14
}

