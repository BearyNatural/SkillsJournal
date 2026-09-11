# Configured within the provider
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Create my private repo
resource "aws_ecr_repository" "lab_repo" {
  name                 = "lab_repo"
  force_delete         = true # this will destroy all images contained within upon terraform destroy
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

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
