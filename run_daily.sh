#!/bin/bash
# Run the Aranet4 Data Saver daily script

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Change to the script directory
cd "$SCRIPT_DIR" || exit 1

# Create logs directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/logs"

# Set timeout value (in seconds)
TIMEOUT=600  # 10 minutes

# Run the script with historical data mode and timeout
if command -v timeout &> /dev/null; then
    # For Linux/macOS with GNU coreutils timeout
    timeout $TIMEOUT ./aranet4_data_saver.py --historical
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        echo "$(date): Script timed out after $TIMEOUT seconds" >> "$SCRIPT_DIR/logs/scheduler.log"
        exit 1
    fi
elif command -v gtimeout &> /dev/null; then
    # For macOS with Homebrew GNU coreutils
    gtimeout $TIMEOUT ./aranet4_data_saver.py --historical
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        echo "$(date): Script timed out after $TIMEOUT seconds" >> "$SCRIPT_DIR/logs/scheduler.log"
        exit 1
    fi
else
    # Fallback for macOS without timeout command - use perl
    perl -e '
        eval {
            local $SIG{ALRM} = sub { die "timeout\n" };
            alarm '$TIMEOUT';
            system("./aranet4_data_saver.py --historical");
            alarm 0;
        };
        if ($@ eq "timeout\n") {
            exit 1;
        }
    '
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 1 ]; then
        echo "$(date): Script may have timed out after $TIMEOUT seconds" >> "$SCRIPT_DIR/logs/scheduler.log"
        exit 1
    fi
fi

# Log the execution status
if [ $EXIT_CODE -eq 0 ]; then
    echo "$(date): Run completed successfully" >> "$SCRIPT_DIR/logs/scheduler.log"
else
    echo "$(date): Run failed with exit code $EXIT_CODE" >> "$SCRIPT_DIR/logs/scheduler.log"
fi
