sudo yum install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl status docker

# Variables
REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# sign into Docker
aws ecr get-login-password --region "$REGION" | sudo docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# docker build make sure you use the right platform
sudo docker build --platform linux/arm64 -t my-arm64-image .
sudo docker inspect my-arm64-image --format '{{.Architecture}}'

# Tag the image (ecr repo) then push
sudo docker tag my-arm64-image ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/docker/largearm64:latest
sudo docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/docker/largearm64:latest

# whatever base image req to run the dockerfile
sudo docker pull public.ecr.aws/aws-observability/aws-otel-collector:v0.41.2 
sudo docker run -it public.ecr.aws/aws-observability/aws-otel-collector:v0.41.2 /bin/bash
rpm -q --changelog libxml2 | grep -i CVE


# for CVE checks on an image that can not be used as a base image in a dockerfile:
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin

trivy image public.ecr.aws/aws-observability/aws-otel-collector:v0.41.2

# check size of image after tagging
sudo docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep largearm64