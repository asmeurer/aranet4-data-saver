#!/usr/bin/env python3
"""
Aranet Data Saver Scheduler

This script helps set up automatic daily execution of the data saver.
It can configure:
1. cron job (for macOS/Linux)
2. launchd service (for macOS)
3. Provides instructions for Windows Task Scheduler
"""

import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path


def setup_cron(script_path, time_str="0 0 * * *"):
    """Set up a cron job to run the data saver daily.

    Args:
        script_path: Path to the run_daily.sh script
        time_str: Cron time specification (default: midnight)
    """
    # Make the script executable
    os.chmod(script_path, 0o755)

    # Get existing crontab
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        current_crontab = result.stdout
    except subprocess.CalledProcessError:
        current_crontab = ""

    # Check if our job is already in crontab
    job_line = f"{time_str} {script_path}"
    if job_line in current_crontab:
        print("Cron job already exists.")
        return

    # Add our job
    new_crontab = current_crontab.strip() + f"\n{job_line}\n"

    # Write new crontab
    try:
        proc = subprocess.Popen(["crontab", "-"], stdin=subprocess.PIPE, text=True)
        proc.communicate(input=new_crontab)

        if proc.returncode == 0:
            print(f"Successfully added cron job: {job_line}")
        else:
            print(f"Failed to add cron job. Return code: {proc.returncode}")
    except Exception as e:
        print(f"Error setting up cron job: {e}")


def setup_launchd(script_path, label="com.user.aranet4.datasaver"):
    """Set up a launchd service for macOS.

    Args:
        script_path: Path to the run_daily.sh script
        label: Service label
    """
    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>{script_path}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>0</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardErrorPath</key>
    <string>{os.path.dirname(script_path)}/logs/launchd_error.log</string>
    <key>StandardOutPath</key>
    <string>{os.path.dirname(script_path)}/logs/launchd_output.log</string>
</dict>
</plist>
"""

    # Ensure logs directory exists
    os.makedirs(f"{os.path.dirname(script_path)}/logs", exist_ok=True)

    # Create plist file
    plist_path = os.path.expanduser(f"~/Library/LaunchAgents/{label}.plist")

    with open(plist_path, "w") as f:
        f.write(plist_content)

    # Load the service
    try:
        subprocess.run(["launchctl", "load", plist_path], check=True)
        print(f"Successfully created and loaded launchd service: {label}")
        print(f"Plist file created at: {plist_path}")
    except subprocess.CalledProcessError as e:
        print(f"Error loading launchd service: {e}")


def show_windows_instructions(script_path):
    """Show instructions for setting up Windows Task Scheduler."""
    print("\nTo set up automatic execution on Windows:")
    print("----------------------------------------")
    print("1. Open Task Scheduler (search for 'Task Scheduler' in the Start menu)")
    print("2. Click 'Create Basic Task' in the right panel")
    print("3. Name it 'Aranet4 Data Saver' and add a description")
    print("4. Set the trigger to 'Daily' and choose a time")
    print("5. For the action, select 'Start a program'")
    print("6. Browse to select python.exe (typically in C:\\Python3x\\python.exe)")
    print(f"7. In 'Add arguments', enter the full path to your script: {script_path}")
    print(f"8. In 'Start in', enter: {os.path.dirname(script_path)}")
    print("9. Complete the wizard\n")


def main():
    """Main entry point for the scheduler script."""
    parser = argparse.ArgumentParser(
        description="Configure automatic execution of Aranet4 Data Saver"
    )
    parser.add_argument(
        "--time", "-t", help="Cron time (e.g., '0 0 * * *' for midnight)", default="0 0 * * *"
    )
    parser.add_argument(
        "--method",
        "-m",
        choices=["cron", "launchd", "windows", "auto"],
        default="auto",
        help="Scheduling method to use",
    )
    args = parser.parse_args()

    # Get the directory where this script is located
    script_dir = Path(__file__).resolve().parent
    run_script_path = script_dir / "run_daily.sh"
    aranet_script_path = script_dir / "aranet_data_saver.py"

    # Check operating system
    system = platform.system()

    if args.method == "auto":
        if system == "Darwin":  # macOS
            method = "launchd"
        elif system == "Linux":
            method = "cron"
        elif system == "Windows":
            method = "windows"
        else:
            print(f"Unsupported operating system: {system}")
            sys.exit(1)
    else:
        method = args.method

    print(f"Setting up automatic execution using {method}...\n")

    if method == "cron":
        setup_cron(str(run_script_path), args.time)
    elif method == "launchd":
        setup_launchd(str(run_script_path))
    elif method == "windows":
        show_windows_instructions(str(aranet_script_path))

    print("\nSetup complete. The script will run daily at midnight.")
    print("Make sure your computer is on at the scheduled time for the script to run.")
    print("You may need to adjust power settings to prevent sleep during scheduled times.")


if __name__ == "__main__":
    main()
