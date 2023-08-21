# Configured within the provider
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Create my private repo
resource "aws_ecr_repository" "lab_repo" {
  name = "lab_repo"
  force_delete = true # this will destroy all images contained within upon terraform destroy
}

# Create IAM policy to allow ECS Fargate to pull image from my account only
resource "aws_ecr_repository_policy" "lab_ecr_policy" {
  repository = aws_ecr_repository.lab_repo.name

  policy = jsonencode({
    Version = "2008-10-17",
    Statement = [
      {
      Sid       = "AllowECSFargatePull",
      Effect    = "Allow",
      Principal = "*",
      Action    = ["*"]
      }
    ]
  })
} # Removed due to issues with the code :'()

# Outputs
output "repo_url" {
  value = aws_ecr_repository.lab_repo.repository_url
}

output "repo_arn" {
  value = aws_ecr_repository.lab_repo.arn
}

output "repo_name" {
  value = aws_ecr_repository.lab_repo.name
}
