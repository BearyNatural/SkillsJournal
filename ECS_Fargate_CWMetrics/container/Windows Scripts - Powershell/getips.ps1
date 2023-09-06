# Define the cluster and service name
$CLUSTER_NAME = "lab_ecs_cluster"
$SERVICE_NAME = "lab_fargate_service"

# Get the task ARNs
$TASK_ARNS = aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --query 'taskArns' --output text

# Convert the space or newline-separated string of ARNs into an array of ARNs
$TASK_ARNS_ARRAY = $TASK_ARNS -split '\s+'  # splits by space or newline

$ENI_IDS = @()  # Declare an empty array to collect ENI IDs

# Loop through the array and describe each task
foreach ($arn in $TASK_ARNS_ARRAY) {
    $ENI_IDS_RAW = aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $arn
    $ENI_ID = ($ENI_IDS_RAW | ConvertFrom-Json).tasks.attachments.details | Where-Object { $_.name -eq "networkInterfaceId" } | ForEach-Object { $_.value }
    $ENI_IDS += $ENI_ID
}

# Clear the content of the file
Clear-Content -Path listofips.txt

# Iterate through ENI IDs to get the public IPs
foreach ($eni in $ENI_IDS) {
    $PUBLIC_IP_RAW = aws ec2 describe-network-interfaces --network-interface-ids $eni
    $PUBLIC_IP = (($PUBLIC_IP_RAW | ConvertFrom-Json).NetworkInterfaces.Association).PublicIp

    # Print the public IP to the file
    Add-Content -Path listofips.txt -Value $PUBLIC_IP
}

Write-Output "IPs saved to listofips.txt"
