#!/bin/bash

# Path to your private key
KEY_PATH="/home/darkeagle/Desktop/myEc2KeyPair.pem"

# Directories for saving outputs
BASE_DIR="/home/darkeagle/Desktop/server_health_outputs"
ALL_DIR="$BASE_DIR/all"
INTERMEDIATE_DIR="$BASE_DIR/intermediate"
CRITICAL_DIR="$BASE_DIR/critical"

# Create directories if they don't exist
mkdir -p "$ALL_DIR"
mkdir -p "$INTERMEDIATE_DIR"
mkdir -p "$CRITICAL_DIR"

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
for SERVER_IP in $SERVER_LIST; do
    echo "Processing server: $SERVER_IP"
    
    # Define the output file paths
    ALL_OUTPUT="$ALL_DIR/server_health_output_$SERVER_IP.txt"
    INTERMEDIATE_OUTPUT="$INTERMEDIATE_DIR/server_health_output_$SERVER_IP.txt"
    CRITICAL_OUTPUT="$CRITICAL_DIR/server_health_output_$SERVER_IP.txt"

    # Execute the health check commands on the server
    ssh -i "$KEY_PATH" ubuntu@$SERVER_IP "
      echo '===== SERVER HEALTH CHECK: $SERVER_IP =====' > /home/ubuntu/server_health_check_$SERVER_IP.txt;
      
      # Disk usage
      echo '*** Disk Usage (df -h) ***' >> /home/ubuntu/server_health_check_$SERVER_IP.txt;
      df -h >> /home/ubuntu/server_health_check_$SERVER_IP.txt;

      # Memory and swap usage
      echo '*** Memory and Swap Usage (free -g) ***' >> /home/ubuntu/server_health_check_$SERVER_IP.txt;
      free -g >> /home/ubuntu/server_health_check_$SERVER_IP.txt;

      # Number of CPUs
      echo '*** Number of CPUs (nproc) ***' >> /home/ubuntu/server_health_check_$SERVER_IP.txt;
      nproc >> /home/ubuntu/server_health_check_$SERVER_IP.txt;

      # Uptime and load averages
      echo '*** Uptime and Load Averages (uptime) ***' >> /home/ubuntu/server_health_check_$SERVER_IP.txt;
      uptime >> /home/ubuntu/server_health_check_$SERVER_IP.txt;
    "

    # Retrieve the output file from the server
    rsync -avz -e "ssh -i $KEY_PATH" ubuntu@$SERVER_IP:/home/ubuntu/server_health_check_$SERVER_IP.txt "$ALL_OUTPUT"

    # Determine where to save the output based on conditions
    if grep -q '100%' "$ALL_OUTPUT"; then
        cp "$ALL_OUTPUT" "$CRITICAL_OUTPUT"
        echo "Critical issue detected on $SERVER_IP. Output saved to $CRITICAL_DIR."
    elif grep -q 'Warning\|Error\|High' "$ALL_OUTPUT"; then
        cp "$ALL_OUTPUT" "$INTERMEDIATE_OUTPUT"
        echo "Intermediate issue detected on $SERVER_IP. Output saved to $INTERMEDIATE_DIR."
    else
        echo "No critical or intermediate issues detected on $SERVER_IP."
    fi

    echo "Health check for $SERVER_IP completed. Output saved to $ALL_DIR."
done
