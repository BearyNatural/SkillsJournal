#!/bin/bash
yum update -y
yum install -y docker
service docker start
usermod -aG docker ec2-user

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Create directory
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app # Change to the directory

# Create the dockerfile
cat <<'EOF' > Dockerfile
${dockerfile}
EOF

# Create the app.py file
cat <<'EOF' > app.py
${app}
EOF

# Login to ECR
$(aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${accountid}.dkr.ecr.${region}.amazonaws.com)

# Build docker image
docker build -t ${reponame} .

# Tag and push the Docker image
docker tag ${reponame}:latest ${accountid}.dkr.ecr.${region}.amazonaws.com/${reponame}:latest

docker push ${accountid}.dkr.ecr.${region}.amazonaws.com/${reponame}:latest

# Shutdown the instance
shutdown -h now