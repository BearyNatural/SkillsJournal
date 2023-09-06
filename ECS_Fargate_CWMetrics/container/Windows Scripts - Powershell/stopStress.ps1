$file = "listofips.txt"

# Check if file exists
if (-not (Test-Path $file)) {
    Write-Output "File $file not found!"
    exit
}

# Read lines from the file
Get-Content $file | ForEach-Object {
    $container_ip = $_.Trim()

    # Check if the line is empty
    if ([string]::IsNullOrEmpty($container_ip)) {
        Write-Output "Empty line encountered. Skipping..."
        continue
    }

    Write-Output "Sending request to stop stress on $container_ip..."
    
    try {
        $response = Invoke-RestMethod -Method Post -Uri "http://${container_ip}:8080/stop_stress"
        Write-Output "Response from $container_ip : $response"
    }
    catch {
        Write-Output "Error sending request to $container_ip : $_"
    }
}
