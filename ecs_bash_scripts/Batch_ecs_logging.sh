#!/bin/bash
set -e

# Configuration variables
AWS_REGION="ap-southeast-2"
JOB_DEFINITION_NAME="hello-world-job"
LOG_GROUP_NAME="/aws/batch/job-logs"
JOB_QUEUE_NAME="test"

echo "Creating AWS Batch job definition for Hello World..."

# Create CloudWatch Logs group if it doesn't exist
aws logs create-log-group --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" || true
aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME" --retention-in-days 365 --region "$AWS_REGION"

# Create AWS Batch job definition
cat > batch-job-definition.json << EOF
{
  "jobDefinitionName": "${JOB_DEFINITION_NAME}",
  "type": "container",
  "containerProperties": {
    "image": "amazonlinux:latest",
    "vcpus": 1,
    "memory": 512,
    "command": [
      "/bin/bash", 
      "-c", 
      "for i in {1..12}; do echo \"Hello World! This is iteration \$i at \$(date)\"; sleep 300; done"
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${LOG_GROUP_NAME}",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "hello-job"
      }
    }
  },
  "timeout": {
    "attemptDurationSeconds": 3900
  },
  "platformCapabilities": [
    "EC2"
  ]
}
EOF

aws batch register-job-definition --cli-input-json file://batch-job-definition.json --region "$AWS_REGION"

echo "Job definition created: $JOB_DEFINITION_NAME"
echo "Now submitting a job..."

# Submit a job
JOB_RESPONSE=$(aws batch submit-job \
  --job-name "hello-world-job-$(date +%s)" \
  --job-queue "$JOB_QUEUE_NAME" \
  --job-definition "$JOB_DEFINITION_NAME" \
  --region "$AWS_REGION")


