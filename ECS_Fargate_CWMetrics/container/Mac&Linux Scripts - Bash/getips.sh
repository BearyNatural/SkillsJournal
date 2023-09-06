#!/bin/bash

# Define the cluster, service name, and profile
CLUSTER_NAME="my-fargate-cluster"
SERVICE_NAME="my-fargate-service"

# Get the task ARNs
TASK_ARNS=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --query 'taskArns' --output text)

# Describe the tasks to get the network interfaces (ENI IDs)
ENI_IDS=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARNS | jq -r '.tasks[].attachments[].details[] | select(.name == "networkInterfaceId") | .value')

# Iterate through ENI IDs to get the public IPs
> listofips.txt
for eni in $ENI_IDS; do
    PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $eni | jq -r '.NetworkInterfaces[].Association.PublicIp')
    
    # Print the public IP to the file
    echo $PUBLIC_IP >> listofips.txt
done

echo "IPs saved to listofips.txt"
