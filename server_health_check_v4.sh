#!/bin/bash

# Parse command-line arguments
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

# Ensure the key path and output directory are set
if [ -z "$KEY_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: $0 -i <path_to_key> -o <output_directory>"
  exit 1
fi

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

# Process each server IP
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
      echo '===== SERVER HEALTH CHECK: $SERVER_IP =====';
      
      echo '';
      echo '*** Disk Usage (df -h) ***';
      DISK_USAGE=\$(df -h);
      echo \"\$DISK_USAGE\";
      
      echo '';
      echo '*** Memory and Swap Usage (free -g) ***';
      MEMORY_USAGE=\$(free -g);
      echo \"\$MEMORY_USAGE\";
      
      echo '';
      echo '*** Number of CPUs (nproc) ***';
      CPU_COUNT=\$(nproc);
      echo \"\$CPU_COUNT\";
      
      echo '';
      echo '*** Uptime and Load Averages (uptime) ***';
      UPTIME_LOAD=\$(uptime);
      echo \"\$UPTIME_LOAD\";
      
      echo '';
      echo '*** Top Memory-Consuming Processes (ps aux --sort=-%mem | head) ***';
      TOP_PROCESSES=\$(ps aux --sort=-%mem | head);
      echo \"\$TOP_PROCESSES\";
      
      echo '';
      if command -v netstat &> /dev/null; then
        OPEN_PORTS=\$(netstat -tuln);
        echo '*** Open Ports and Services (netstat -tuln) ***';
        echo \"\$OPEN_PORTS\";
      elif command -v ss &> /dev/null; then
        OPEN_PORTS=\$(ss -tuln);
        echo '*** Open Ports and Services (ss -tuln) ***';
        echo \"\$OPEN_PORTS\";
      else
        echo 'Neither netstat nor ss is available on this system.';
      fi
      
      echo '';
      if [ -f /var/log/syslog ]; then
        LOG_ENTRIES=\$(tail -n 5 /var/log/syslog);
        echo '*** Recent System Log Entries (tail -n 100 /var/log/syslog) ***';
        echo \"\$LOG_ENTRIES\";
      elif [ -f /var/log/messages ]; then
        LOG_ENTRIES=\$(tail -n 5 /var/log/messages);
        echo '*** Recent System Log Entries (tail -n 100 /var/log/messages) ***';
        echo \"\$LOG_ENTRIES\";
      else
        echo 'No system log file found.';
      fi
      
      echo '===== END OF CHECK =====';
    " > "$OUTPUT_FILE"

    # Categorize the output based on criteria
    DISK_USAGE=$(grep "Disk Usage" "$OUTPUT_FILE")
    UPTIME_LOAD=$(grep "Uptime and Load Averages" "$OUTPUT_FILE")

    if grep -q "100%" <<< "$DISK_USAGE"; then
        mv "$OUTPUT_FILE" "$CRITICAL_DIR/"
    elif grep -q "load average:" <<< "$UPTIME_LOAD" && [[ "$(echo $UPTIME_LOAD | awk '{print $10}')" > 2.0 ]]; then
        mv "$OUTPUT_FILE" "$INTERMEDIATE_DIR/"
    else
        mv "$OUTPUT_FILE" "$ALL_DIR/"
    fi

    echo "Health check for $SERVER_IP completed. Output categorized and saved."
done

