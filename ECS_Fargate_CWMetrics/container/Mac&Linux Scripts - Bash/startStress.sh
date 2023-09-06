#!/bin/bash

file="listofips.txt"

if [ ! -f "$file" ]; then
    echo "File $file not found!"
    exit 1
fi

while IFS= read -r container_ip
do
    if [ -z "$container_ip" ]; then
        echo "Empty line encountered. Skipping..."
        continue
    fi

    echo "Sending request to start stress on $container_ip..."
    response=$(curl -X POST "http://${container_ip}:8080/start_stress?cpu=2")
    echo "Response from $container_ip: $response"
done < "$file"
