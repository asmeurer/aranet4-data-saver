#!/usr/bin/env python3
"""
Aranet4 Data Saver Runner

This script provides a convenient way to run the Aranet4 Data Saver
using uv for dependency management.
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Run Aranet4 Data Saver")
    parser.add_argument(
        "--config", "-c",
        help="Path to config file (default: config/local_config.yaml)",
        default=os.path.join("config", "local_config.yaml")
    )
    parser.add_argument(
        "--install", "-i",
        action="store_true",
        help="Install dependencies before running"
    )
    parser.add_argument(
        "--historical", "-H",
        action="store_true",
        help="Only fetch historical data and exit"
    )
    parser.add_argument(
        "--configure", "-C",
        action="store_true",
        help="Run interactive configuration wizard"
    )
    return parser.parse_args()


def ensure_dependencies():
    """Ensure all dependencies are installed using uv."""
    print("Installing dependencies with uv...")
    
    # Get the root directory of the project
    root_dir = Path(__file__).resolve().parent
    requirements_file = root_dir / "requirements.txt"
    
    try:
        # Run uv pip install
        result = subprocess.run(
            ["uv", "pip", "install", "-r", str(requirements_file)],
            check=True,
            capture_output=True,
            text=True
        )
        print(result.stdout)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error installing dependencies: {e}")
        print(e.stderr)
        return False
    except FileNotFoundError:
        print("Error: 'uv' command not found. Please install uv first.")
        print("You can install it with: pip install uv")
        return False


def run_data_saver(config_path, historical_only=False, configure=False):
    """Run the Aranet4 data saver script."""
    # Get the root directory and script path
    root_dir = Path(__file__).resolve().parent
    script_path = root_dir / "src" / "aranet_data_saver.py"
    
    # Ensure the config path is absolute
    if not os.path.isabs(config_path):
        config_path = os.path.join(root_dir, config_path)
    
    if configure:
        print(f"Running Aranet4 Data Saver configuration wizard")
    else:
        print(f"Running Aranet4 Data Saver with config: {config_path}")
    
    try:
        # Use uv run to execute the script
        cmd = ["uv", "run", str(script_path), config_path]
        if historical_only:
            cmd.append("--historical-only")
        if configure:
            cmd.append("--configure")
            
        # Run the command
        subprocess.run(cmd, check=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error running data saver: {e}")
        return False
    except KeyboardInterrupt:
        print("\nData collection stopped by user")
        return True


def main():
    """Main entry point."""
    args = parse_args()
    
    # Install dependencies if requested
    if args.install:
        if not ensure_dependencies():
            sys.exit(1)
    
    # Run the data saver
    success = run_data_saver(args.config, args.historical, args.configure)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()