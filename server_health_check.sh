#!/bin/bash

# Path to your private key
KEY_PATH="/home/darkeagle/Desktop/myEc2KeyPair.pem"

# Fetch the list of running EC2 instance IPs
SERVER_LIST=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output text)

# Check if the server list is empty
if [ -z "$SERVER_LIST" ]; then
  echo "No running EC2 instances found."
  exit 1
fi

# Loop through each server IP in the list
# Use tr to replace tabs and spaces with newlines, ensuring each IP is processed correctly
echo "Server List: $SERVER_LIST"

# Convert tabs to newlines to handle multiple IPs correctly
SERVER_LIST=$(echo "$SERVER_LIST" | tr '\t' '\n' | tr ' ' '\n')

for SERVER_IP in $SERVER_LIST; do
    # Trim any leading or trailing whitespace (just in case)
    SERVER_IP=$(echo "$SERVER_IP" | xargs)
    
    # Print the IP to check if it’s correct
    echo "Processing server: '$SERVER_IP'"

    # Ensure SERVER_IP is not empty
    if [ -z "$SERVER_IP" ]; then
        echo "Empty IP address found. Skipping..."
        continue
    fi

    # Send the script to the server
    rsync -avz -e "ssh -i $KEY_PATH" /home/darkeagle/Desktop/scripts/server_health_check.sh ubuntu@$SERVER_IP:/home/ubuntu/

    # Execute the script on the server and retrieve the output
    # ssh -i "$KEY_PATH" ubuntu@$SERVER_IP "bash /home/ubuntu/server_health_check.sh" > "/home/darkeagle/Desktop/server_health_output_$SERVER_IP.txt"
    
# Execute the health check script on the server and retrieve the output
ssh -i "$KEY_PATH" ubuntu@$SERVER_IP "bash /home/ubuntu/server_health_check.sh; df -h; free -g; nproc" > "/home/darkeagle/Desktop/servers-health/server_health_output_$SERVER_IP.txt"



    echo "Health check for $SERVER_IP completed. Output saved to /home/darkeagle/Desktop/server_health_output_$SERVER_IP.txt"
done





