#!/bin/bash
# Script to run the Aranet4 Data Saver daily
# This will be called by cron

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change to the script directory
cd "$SCRIPT_DIR" || exit 1

# Run the Aranet4 Data Saver
python3 aranet_data_saver.py

# Alternatively, you can use the following line if you want to use the uv shebang:
# ./aranet_data_saver.py

# Log the execution
echo "$(date): Aranet4 Data Saver executed" >> "$SCRIPT_DIR/logs/cron_execution.log"
