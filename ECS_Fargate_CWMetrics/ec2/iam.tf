# IAM policy for ec2 
resource "aws_iam_role" "ec2_role" {
  name = "EC2DockerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Effect = "Allow",
    }]
  })
}

# IAM role for ec2
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "EC2DockerProfile"
  role = aws_iam_role.ec2_role.name
}

# IAM permissions for ec2
resource "aws_iam_role_policy" "ec2_policy" {
  name = "EC2DockerPolicy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      Resource = "*", # cut this to least priv also
      Effect   = "Allow",
    }]
  })
}

# For SSM access to contianer if needed ;)
data "aws_iam_policy" "ssm_policy" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach it to the container
resource "aws_iam_role_policy_attachment" "ssm_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = data.aws_iam_policy.ssm_policy.arn
}