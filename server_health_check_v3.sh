#!/bin/bash

while getopts "i:o:" opt; do
  case ${opt} in
    i )
      KEY_PATH=$OPTARG
      ;;
    o )
      OUTPUT_DIR=$OPTARG
      ;;
    \? )
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    : )
      echo "Invalid option: -$OPTARG requires an argument" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Fetch the list of running EC2 instance IPs
SERVER_LIST=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output text)

if [ -z "$SERVER_LIST" ]; then
  echo "No running EC2 instances found."
  exit 1
fi

SERVER_LIST=$(echo "$SERVER_LIST" | tr '\t' '\n' | tr ' ' '\n')

for SERVER_IP in $SERVER_LIST; do
    echo "Processing server: '$SERVER_IP'"
    
    if [ -z "$SERVER_IP" ]; then
        echo "Empty IP address found. Skipping..."
        continue
    fi

    # Send the script to the server
    rsync -avz -e "ssh -i $KEY_PATH" /home/ubuntu/server_health_check.sh ubuntu@$SERVER_IP:/home/ubuntu/

    # Execute the health check script on the server and retrieve the output
    ssh -i "$KEY_PATH" ubuntu@$SERVER_IP "
      echo '===== SERVER HEALTH CHECK: $SERVER_IP =====';
      
      echo '';
      echo '*** Disk Usage (df -h) ***';
      df -h;
      
      echo '';
      echo '*** Memory and Swap Usage (free -g) ***';
      free -g;
      
      echo '';
      echo '*** Number of CPUs (nproc) ***';
      nproc;
      
      echo '';
      echo '*** Uptime and Load Averages (uptime) ***';
      uptime;
      
      echo '';
      echo '*** Top Memory-Consuming Processes (ps aux --sort=-%mem | head) ***';
      ps aux --sort=-%mem | head;
      
      echo '';
      echo '*** Open Ports and Services (netstat -tuln) ***';
      netstat -tuln;
      
      echo '';
      echo '*** Recent System Log Entries (tail -n 100 /var/log/syslog) ***';
      tail -n 5 /var/log/syslog;
      
      echo '===== END OF CHECK =====';
    " > "$OUTPUT_DIR/server_health_output_$SERVER_IP.txt"

    echo "Health check for $SERVER_IP completed. Output saved to $OUTPUT_DIR/server_health_output_$SERVER_IP.txt"
done
