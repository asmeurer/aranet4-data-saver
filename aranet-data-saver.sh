#!/bin/bash
# Simple wrapper to run the Aranet4 Data Saver with uv

# Get directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Run the script with uv
uv run "$SCRIPT_DIR/run.py" "$@"