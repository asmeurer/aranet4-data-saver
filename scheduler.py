#!/usr/bin/env python3
"""
Aranet Data Saver Scheduler

This script helps set up automatic daily execution of the data saver.
It can configure:
1. cron job (for macOS/Linux)
2. launchd service (for macOS)
3. Provides instructions for Windows Task Scheduler

The scheduler runs the data saver in historical-only mode, which collects
all available data since the last run and then exits. A timeout of 10 minutes
is applied to prevent hanging, and errors are logged to the logs directory.
"""

import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path


def ensure_log_directory(script_dir):
    """Ensure the logs directory exists."""
    log_dir = os.path.join(script_dir, "logs")
    os.makedirs(log_dir, exist_ok=True)
    return log_dir


def setup_cron(script_path, time_str="0 0 * * *"):
    """Set up a cron job to run the data saver daily.

    Args:
        script_path: Path to the aranet4_data_saver script
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
    old_job_pattern = f" {script_path}"  # Match any job with our script path

    has_existing_job = False
    new_crontab_lines = []

    # Parse the current crontab line by line
    for line in current_crontab.splitlines():
        # If line contains our script path but isn't identical to the new job
        if old_job_pattern in line and line != job_line:
            print(f"Updating existing cron job: {line} -> {job_line}")
            has_existing_job = True
            new_crontab_lines.append(job_line)
        elif line == job_line:
            # If job is identical, keep it but mark as existing
            has_existing_job = True
            new_crontab_lines.append(line)
        elif line.strip():  # Keep all non-empty lines
            new_crontab_lines.append(line)

    # If no existing job found, add the new job
    if not has_existing_job:
        print(f"Adding new cron job: {job_line}")
        new_crontab_lines.append(job_line)
    elif job_line in new_crontab_lines:
        print("Cron job already exists with the correct settings.")
        return

    # Create the new crontab content
    new_crontab = "\n".join(new_crontab_lines) + "\n"

    # Write new crontab
    try:
        proc = subprocess.Popen(["crontab", "-"], stdin=subprocess.PIPE, text=True)
        proc.communicate(input=new_crontab)

        if proc.returncode == 0:
            if has_existing_job:
                print("Successfully updated cron job")
            else:
                print(f"Successfully added cron job: {job_line}")
        else:
            print(f"Failed to update cron job. Return code: {proc.returncode}")
    except Exception as e:
        print(f"Error setting up cron job: {e}")


def setup_launchd(script_path, label="com.aranet4.datasaver"):
    """Set up a launchd service for macOS.

    The service uses a specially named script (aranet4_data_saver) to display
    a proper name in macOS System Settings instead of "bash". It also runs with
    a low priority (nice 10) to minimize system impact.

    Args:
        script_path: Path to the aranet4_data_saver script
        label: Service label (use reverse domain name notation)
    """
    script_dir = os.path.dirname(script_path)
    log_dir = ensure_log_directory(script_dir)

    # Use aranet4_data_saver directly
    scheduler_path = os.path.join(os.path.dirname(script_path), "aranet4_data_saver")

    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{scheduler_path}</string>
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
    <string>{log_dir}/launchd_error.log</string>
    <key>StandardOutPath</key>
    <string>{log_dir}/launchd_output.log</string>
    <key>ExitTimeOut</key>
    <integer>900</integer>
    <key>TimeOut</key>
    <integer>900</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>ServiceDescription</key>
    <string>Aranet4 Data Saver</string>
    <key>Nice</key>
    <integer>10</integer>
</dict>
</plist>
"""

    # Create plist file
    plist_path = os.path.expanduser(f"~/Library/LaunchAgents/{label}.plist")

    # Check if service already exists
    service_exists = False
    try:
        # Check if the plist file exists
        if os.path.exists(plist_path):
            service_exists = True

            # Try to read existing file content to compare
            with open(plist_path, "r") as f:
                existing_content = f.read()

            if existing_content.strip() == plist_content.strip():
                print("Launchd service already exists with the correct configuration.")
                return
            else:
                print("Updating existing launchd service configuration...")
                # Try to unload existing service
                try:
                    subprocess.run(
                        ["launchctl", "unload", plist_path], check=False, capture_output=True
                    )
                except Exception:
                    # It's okay if unload fails, as it might not be loaded
                    pass
    except Exception as e:
        print(f"Error checking existing launchd service: {e}")

    # Write the new plist file
    with open(plist_path, "w") as f:
        f.write(plist_content)

    # Load the service
    try:
        subprocess.run(["launchctl", "load", plist_path], check=True)
        if service_exists:
            print(f"Successfully updated and reloaded launchd service: {label}")
        else:
            print(f"Successfully created and loaded launchd service: {label}")
        print(f"Plist file at: {plist_path}")
    except subprocess.CalledProcessError as e:
        print(f"Error loading launchd service: {e}")


def show_windows_instructions(script_path):
    """Show instructions for setting up Windows Task Scheduler."""
    # Create wrapper batch file for Windows with timeout
    script_dir = os.path.dirname(script_path)
    log_dir = ensure_log_directory(script_dir)
    batch_path = os.path.join(script_dir, "aranet4_data_saver.bat")

    log_file = os.path.join(log_dir, "scheduler.log").replace("/", "\\")
    log_dir_windows = log_dir.replace("/", "\\")
    sys_executable = sys.executable
    script_path_str = str(script_path)

    # Create new batch file content using raw string to avoid f-string backslash issues
    batch_content = f"""@echo off
REM Run the Aranet4 Data Saver with timeout protection
if not exist "{log_dir_windows}" mkdir "{log_dir_windows}"
echo Starting Aranet4 Data Saver at %date% %time% > "{log_file}"

REM Create timeout protection using Windows timeout command (10 minutes)
start /b "" cmd /c "timeout /t 600 /nobreak > nul & taskkill /f /im python.exe /fi "WINDOWTITLE eq Aranet4*" > nul 2>&1"

REM Run the script in historical mode
"{sys_executable}" "{script_path_str}" --historical

if %ERRORLEVEL% equ 0 (
    echo Run completed successfully at %date% %time% >> "{log_file}"
) else (
    echo Run failed with exit code %ERRORLEVEL% at %date% %time% >> "{log_file}"
)
"""

    # Check if batch file already exists and compare
    batch_exists = os.path.exists(batch_path)
    should_update = True

    if batch_exists:
        try:
            with open(batch_path, "r") as f:
                existing_content = f.read()

            if existing_content.strip() == batch_content.strip():
                print(
                    f"Windows batch file already exists with the correct configuration at: {batch_path}"
                )
                should_update = False
            else:
                print(f"Updating existing Windows batch file at: {batch_path}")
        except Exception as e:
            print(f"Error checking existing batch file: {e}")

    # Write the batch file if needed
    if should_update:
        with open(batch_path, "w") as f:
            f.write(batch_content)
            if batch_exists:
                print(f"Updated Windows batch file with timeout protection at: {batch_path}")
            else:
                print(f"Created Windows batch file with timeout protection at: {batch_path}")

    # Determine if this is first-time setup or an update
    if batch_exists:
        print("\nTo update your existing Windows Task Scheduler task:")
        print("-----------------------------------------------")
        print("1. Open Task Scheduler (search for 'Task Scheduler' in the Start menu)")
        print("2. Find your existing 'Aranet4 Data Saver' task in the Task Scheduler Library")
        print("3. Right-click on the task and select 'Properties'")
        print("4. Verify the batch file path points to the correct location:")
        print(f"   {batch_path}")
        print("5. Go to the 'Settings' tab and check 'Stop the task if it runs longer than:'")
        print("6. Set it to 15 minutes (longer than the internal batch file timeout)")
        print("7. Click 'OK' to save the changes")
    else:
        print("\nTo set up automatic execution on Windows:")
        print("----------------------------------------")
        print("1. Open Task Scheduler (search for 'Task Scheduler' in the Start menu)")
        print("2. Click 'Create Basic Task' in the right panel")
        print("3. Name it 'Aranet4 Data Saver' and add a description")
        print("4. Set the trigger to 'Daily' and choose a time")
        print("5. For the action, select 'Start a program'")
        print(f"6. Browse to select the batch file: {batch_path}")
        print(f"7. In 'Start in', enter: {os.path.dirname(script_path)}")
        print(
            "8. After completing the wizard, right-click on the created task and select 'Properties'"
        )
        print("9. Go to the 'Settings' tab and check 'Stop the task if it runs longer than:'")
        print(
            "10. Set it to 15 minutes (longer than the batch file timeout to allow for proper cleanup)"
        )
        print("11. Click 'OK' to save the changes")


def detect_existing_scheduler():
    """Detect which scheduler might already be set up."""
    system = platform.system()
    script_dir = Path(__file__).resolve().parent
    scheduler_path = script_dir / "aranet4_data_saver"
    batch_path = script_dir / "aranet4_data_saver.bat"

    # Check for existing implementations
    has_cron = False
    has_launchd = False
    has_windows = False

    # Check for cron job (Linux/macOS)
    if system in ["Darwin", "Linux"]:
        try:
            result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
            if str(scheduler_path) in result.stdout:
                has_cron = True
        except Exception:
            pass  # Ignore errors in detection

    # Check for launchd job (macOS)
    if system == "Darwin":
        plist_path = os.path.expanduser("~/Library/LaunchAgents/com.aranet4.datasaver.plist")
        # Also check old plist path for backward compatibility
        old_plist_path = os.path.expanduser(
            "~/Library/LaunchAgents/com.user.aranet4.datasaver.plist"
        )
        if os.path.exists(plist_path) or os.path.exists(old_plist_path):
            has_launchd = True

    # Check for Windows batch file
    if os.path.exists(batch_path):
        has_windows = True

    return {"cron": has_cron, "launchd": has_launchd, "windows": has_windows}


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
    parser.add_argument(
        "--force-update",
        "-f",
        action="store_true",
        help="Force update of existing scheduler configuration",
    )
    args = parser.parse_args()

    # Get the directory where this script is located
    script_dir = Path(__file__).resolve().parent
    scheduler_path = script_dir / "aranet4_data_saver"
    aranet_script_path = script_dir / "aranet_data_saver.py"

    # Make sure the scheduler script is executable
    if os.path.exists(scheduler_path):
        os.chmod(scheduler_path, 0o755)

    # Check operating system
    system = platform.system()

    # Detect existing schedulers
    existing = detect_existing_scheduler()

    # Determine which method to use
    if args.method == "auto":
        if system == "Darwin":  # macOS
            if existing["launchd"]:
                method = "launchd"  # Prefer updating launchd on macOS
            elif existing["cron"]:
                method = "cron"  # Fall back to cron if that's what's set up
            else:
                method = "launchd"  # Default for macOS
        elif system == "Linux":
            method = "cron"
        elif system == "Windows":
            method = "windows"
        else:
            print(f"Unsupported operating system: {system}")
            sys.exit(1)
    else:
        method = args.method

    # If existing schedulers don't match the chosen method, warn the user
    other_existing = [m for m, exists in existing.items() if exists and m != method]
    if other_existing and not args.force_update:
        print(
            f"WARNING: Detected existing scheduler configuration(s) using: {', '.join(other_existing)}"
        )
        print(f"You're about to set up using: {method}")
        print("This could result in multiple schedulers running the same task.")
        choice = input("Continue anyway? (y/n, or 'f' to force update all): ")
        if choice.lower() == "f":
            args.force_update = True
        elif choice.lower() not in ["y", "yes"]:
            print("Operation cancelled.")
            sys.exit(0)

    print(f"Setting up automatic execution using {method}...\n")

    if method == "cron":
        setup_cron(str(scheduler_path), args.time)
    elif method == "launchd":
        setup_launchd(str(scheduler_path))
    elif method == "windows":
        show_windows_instructions(str(aranet_script_path))

    # If force update is enabled, update all other existing methods too
    if args.force_update:
        other_methods = [
            m
            for m in ["cron", "launchd", "windows"]
            if m != method and (existing[m] or system in ["Darwin", "Linux", "Windows"])
        ]

        for other_method in other_methods:
            # Only update methods that make sense for this OS
            if other_method == "cron" and system in ["Darwin", "Linux"]:
                print("\nAlso updating cron configuration...")
                setup_cron(str(scheduler_path), args.time)
            elif other_method == "launchd" and system == "Darwin":
                print("\nAlso updating launchd configuration...")
                setup_launchd(str(scheduler_path))
            elif other_method == "windows" and system == "Windows":
                print("\nAlso updating Windows batch file...")
                show_windows_instructions(str(aranet_script_path))

    print("\nSetup complete. The script will run daily at midnight.")
    print("Make sure your computer is on at the scheduled time for the script to run.")
    print("You may need to adjust power settings to prevent sleep during scheduled times.")
    print("\nThe automated execution includes:")
    print("- A 10-minute timeout to prevent script hanging")
    print("- Automatic error logging to the logs directory")
    print("- Historical-only data collection mode to efficiently capture all new readings")
    print(f"- Log files will be stored in: {os.path.join(script_dir, 'logs')}")

    # Special message for launchd users
    if method == "launchd":
        print(
            "\nNote: The service will appear as 'aranet4_data_saver' in macOS System Settings > Login Items."
        )


if __name__ == "__main__":
    main()
