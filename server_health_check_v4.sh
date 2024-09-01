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

# Create folders for categorized output
ALL_DIR="$OUTPUT_DIR/all"
INTERMEDIATE_DIR="$OUTPUT_DIR/intermediate"
CRITICAL_DIR="$OUTPUT_DIR/critical"

mkdir -p "$ALL_DIR" "$INTERMEDIATE_DIR" "$CRITICAL_DIR"

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

    # Detect the distribution of the remote server
    DISTRO=$(ssh -i "$KEY_PATH" ubuntu@$SERVER_IP "grep '^ID=' /etc/os-release | cut -d '=' -f 2 | tr -d '\"'")

    if [ "$DISTRO" == "amzn" ]; then
        USER="ec2-user"
    elif [ "$DISTRO" == "centos" ] || [ "$DISTRO" == "rhel" ]; then
        USER="centos"
    else
        USER="ubuntu"
    fi

    # Send the script to the server
    rsync -avz -e "ssh -i $KEY_PATH" /home/$USER/server_health_check.sh $USER@$SERVER_IP:/home/$USER/

    # Execute the health check script on the server and retrieve the output
    OUTPUT_FILE="$OUTPUT_DIR/server_health_output_$SERVER_IP.txt"
    ssh -i "$KEY_PATH" $USER@$SERVER_IP "
      echo '===== SERVER HEALTH CHECK: $SERVER_IP =====' > server_health_output.txt;
      
      echo '' >> server_health_output.txt;
      echo '*** Disk Usage (df -h) ***' >> server_health_output.txt;
      DISK_USAGE=\$(df -h);
      echo \"\$DISK_USAGE\" >> server_health_output.txt;
      
      echo '' >> server_health_output.txt;
      echo '*** Memory and Swap Usage (free -g) ***' >> server_health_output.txt;
      MEMORY_USAGE=\$(free -g);
      echo \"\$MEMORY_USAGE\" >> server_health_output.txt;
      
      echo '' >> server_health_output.txt;
      echo '*** Number of CPUs (nproc) ***' >> server_health_output.txt;
      CPU_COUNT=\$(nproc);
      echo \"\$CPU_COUNT\" >> server_health_output.txt;
      
      echo '' >> server_health_output.txt;
      echo '*** Uptime and Load Averages (uptime) ***' >> server_health_output.txt;
      UPTIME_LOAD=\$(uptime);
      echo \"\$UPTIME_LOAD\" >> server_health_output.txt;
      
      echo '' >> server_health_output.txt;
      echo '*** Top Memory-Consuming Processes (ps aux --sort=-%mem | head) ***' >> server_health_output.txt;
      TOP_PROCESSES=\$(ps aux --sort=-%mem | head);
      echo \"\$TOP_PROCESSES\" >> server_health_output.txt;
      
      echo '' >> server_health_output.txt;
      if command -v netstat &> /dev/null; then
        OPEN_PORTS=\$(netstat -tuln);
        echo '*** Open Ports and Services (netstat -tuln) ***' >> server_health_output.txt;
        echo \"\$OPEN_PORTS\" >> server_health_output.txt;
      elif command -v ss &> /dev/null; then
        OPEN_PORTS=\$(ss -tuln);
        echo '*** Open Ports and Services (ss -tuln) ***' >> server_health_output.txt;
        echo \"\$OPEN_PORTS\" >> server_health_output.txt;
      else
        echo 'Neither netstat nor ss is available on this system.' >> server_health_output.txt;
      fi
      
      echo '' >> server_health_output.txt;
      if [ -f /var/log/syslog ]; then
        LOG_ENTRIES=\$(tail -n 5 /var/log/syslog);
        echo '*** Recent System Log Entries (tail -n 100 /var/log/syslog) ***' >> server_health_output.txt;
        echo \"\$LOG_ENTRIES\" >> server_health_output.txt;
      elif [ -f /var/log/messages ]; then
        LOG_ENTRIES=\$(tail -n 5 /var/log/messages);
        echo '*** Recent System Log Entries (tail -n 100 /var/log/messages) ***' >> server_health_output.txt;
        echo \"\$LOG_ENTRIES\" >> server_health_output.txt;
      else
        echo 'No system log file found.' >> server_health_output.txt;
      fi
      
      echo '===== END OF CHECK =====' >> server_health_output.txt;
      
      # Returning relevant outputs for categorization
      echo \"\$DISK_USAGE\";
      echo \"\$UPTIME_LOAD\";
    " > "$OUTPUT_FILE"

    # Capture DISK_USAGE and UPTIME_LOAD for categorization
    DISK_USAGE=$(ssh -i "$KEY_PATH" $USER@$SERVER_IP "df -h")
    UPTIME_LOAD=$(ssh -i "$KEY_PATH" $USER@$SERVER_IP "uptime")

    # Categorize the output based on criteria
    if grep -q "100%" <<< "$DISK_USAGE"; then
        mv "$OUTPUT_FILE" "$CRITICAL_DIR/"
    elif grep -q "load average:" <<< "$UPTIME_LOAD" && [[ "$(echo $UPTIME_LOAD | awk '{print $10}')" > 2.0 ]]; then
        mv "$OUTPUT_FILE" "$INTERMEDIATE_DIR/"
    else
        mv "$OUTPUT_FILE" "$ALL_DIR/"
    fi

    echo "Health check for $SERVER_IP completed. Output categorized and saved."
done
