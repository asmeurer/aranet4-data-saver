#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.6"
# dependencies = ["aranet4", "pyyaml"]
# ///

"""
Aranet4 Data Saver

This script polls an Aranet4 device for sensor data and saves it to disk.
It can be run directly or as a Python module.

Usage:
  ./aranet_data_saver.py [options]
  python -m aranet_data_saver [options]

Options:
  -c, --config PATH    Path to config file (default: config/local_config.yaml)
  -i, --install        Install dependencies before running
  -H, --historical     Only fetch historical data and exit
  -C, --configure      Run interactive configuration wizard
  -h, --help           Show this help message
"""

import os
import sys
import time
import logging
import datetime
import json
import csv
import yaml
import argparse
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple


class Aranet4DataSaver:
    """Main class for saving Aranet4 data."""

    def __init__(self, config_path: str):
        """Initialize with configuration file path."""
        self.config = self._load_config(config_path)
        self._setup_logging()
        self.data_buffer = []
        self.logger.info("Aranet4 Data Saver initialized")
        self.logger.debug(f"Using configuration: {self.config}")

    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from YAML file."""
        try:
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)
            return config
        except Exception as e:
            print(f"Error loading configuration: {e}")
            sys.exit(1)

    def _setup_logging(self):
        """Set up logging based on configuration."""
        log_config = self.config.get('logging', {})
        log_level = getattr(logging, log_config.get('level', 'INFO'))
        log_file = log_config.get('file', '../logs/aranet_data_saver.log')
        
        # Ensure log directory exists
        log_dir = os.path.dirname(log_file)
        os.makedirs(log_dir, exist_ok=True)
        
        # Set up logging
        logging.basicConfig(
            level=log_level,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger('aranet4_data_saver')

    def get_current_readings(self) -> Dict[str, Any]:
        """Get current readings from the Aranet4 device."""
        # Import aranet4 here to allow script to run without it when only installing deps
        import aranet4
        
        device_mac = self.config['device']['mac_address']
        collect_config = self.config['data_collection']['collect']
        
        try:
            self.logger.debug(f"Connecting to Aranet4 device at {device_mac}")
            current = aranet4.client.get_current_readings(device_mac)
            
            # Format readings according to configuration
            readings = {
                'timestamp': datetime.datetime.now().isoformat(),
                'device_mac': device_mac
            }
            
            if collect_config.get('co2', True):
                readings['co2'] = current.co2
            
            if collect_config.get('temperature', True):
                readings['temperature'] = current.temperature
            
            if collect_config.get('humidity', True):
                readings['humidity'] = current.humidity
            
            if collect_config.get('pressure', True):
                readings['pressure'] = current.pressure
            
            self.logger.debug(f"Retrieved readings: {readings}")
            return readings
            
        except Exception as e:
            self.logger.error(f"Error getting readings: {e}")
            return {
                'timestamp': datetime.datetime.now().isoformat(),
                'device_mac': device_mac,
                'error': str(e)
            }

    def get_historical_data(self) -> List[Dict[str, Any]]:
        """Get historical data from the Aranet4 device."""
        # Import aranet4 here to allow script to run without it when only installing deps
        import aranet4
        
        device_mac = self.config['device']['mac_address']
        collect_config = self.config['data_collection']['collect']
        
        # Prepare filter based on configuration
        entry_filter = {
            "co2": collect_config.get('co2', True),
            "temp": collect_config.get('temperature', True),
            "humi": collect_config.get('humidity', True),
            "pres": collect_config.get('pressure', True),
        }
        
        try:
            self.logger.info(f"Downloading historical data from device {device_mac}")
            history = aranet4.client.get_all_records(device_mac, entry_filter=entry_filter)
            
            # Format the history data
            formatted_history = []
            # Use history.value (the list of RecordItem objects), not history itself
            for entry in history.value:
                record = {
                    'timestamp': entry.date.isoformat(),  # Use entry.date, not entry.timestamp
                    'device_mac': device_mac
                }
                
                if collect_config.get('co2', True):
                    record['co2'] = entry.co2
                
                if collect_config.get('temperature', True):
                    record['temperature'] = entry.temperature
                
                if collect_config.get('humidity', True):
                    record['humidity'] = entry.humidity
                
                if collect_config.get('pressure', True):
                    record['pressure'] = entry.pressure
                
                formatted_history.append(record)
            
            self.logger.info(f"Downloaded {len(formatted_history)} historical records")
            return formatted_history
            
        except Exception as e:
            self.logger.error(f"Error getting historical data: {e}")
            return []

    def add_to_buffer(self, readings: Dict[str, Any]):
        """Add readings to the data buffer."""
        self.data_buffer.append(readings)
        buffer_size = self.config['data_collection'].get('buffer_size', 10)
        
        if len(self.data_buffer) >= buffer_size:
            self.save_data()

    def save_data(self):
        """Save buffered data to disk."""
        if not self.data_buffer:
            self.logger.debug("No data to save")
            return
            
        storage_config = self.config['storage']
        data_dir = storage_config.get('data_dir', '../data')
        file_format = storage_config.get('file_format', 'csv')
        
        # Ensure data directory exists
        os.makedirs(data_dir, exist_ok=True)
        
        # Determine filename
        today = datetime.datetime.now().strftime('%Y-%m-%d')
        device_mac = self.config['device']['mac_address']
        device_name = device_mac.replace(':', '')
        
        file_pattern = storage_config.get('file_pattern', 'aranet4_data_{date}.{format}')
        filename = file_pattern.format(
            date=today,
            time=datetime.datetime.now().strftime('%H-%M-%S'),
            device_name=device_name,
            format=file_format
        )
        
        filepath = os.path.join(data_dir, filename)
        
        try:
            if file_format.lower() == 'json':
                self._save_as_json(filepath)
            else:  # Default to CSV
                self._save_as_csv(filepath)
                
            self.logger.info(f"Saved {len(self.data_buffer)} records to {filepath}")
            self.data_buffer = []  # Clear buffer after saving
            
        except Exception as e:
            self.logger.error(f"Error saving data: {e}")

    def _save_as_json(self, filepath: str):
        """Save data buffer as JSON."""
        # Check if file exists to determine if we need to append
        file_exists = os.path.exists(filepath)
        
        if file_exists:
            # Read existing data
            with open(filepath, 'r') as f:
                try:
                    existing_data = json.load(f)
                except json.JSONDecodeError:
                    existing_data = []
            
            # Append new data
            combined_data = existing_data + self.data_buffer
            
            # Write back
            with open(filepath, 'w') as f:
                json.dump(combined_data, f, indent=2)
        else:
            # Create new file
            with open(filepath, 'w') as f:
                json.dump(self.data_buffer, f, indent=2)

    def _save_as_csv(self, filepath: str):
        """Save data buffer as CSV."""
        file_exists = os.path.exists(filepath)
        
        # Get all possible field names from data
        fieldnames = set()
        for reading in self.data_buffer:
            fieldnames.update(reading.keys())
        fieldnames = sorted(list(fieldnames))
        
        # Ensure timestamp is the first column
        if 'timestamp' in fieldnames:
            fieldnames.remove('timestamp')
            fieldnames = ['timestamp'] + fieldnames
        
        mode = 'a' if file_exists else 'w'
        with open(filepath, mode, newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            
            # Write header only for new files
            if not file_exists:
                writer.writeheader()
                
            writer.writerows(self.data_buffer)

    def run(self):
        """Main execution loop."""
        polling_interval = self.config['data_collection'].get('polling_interval', 300)
        
        self.logger.info(f"Starting data collection with {polling_interval}s interval")
        
        # Initial download of historical data
        historical_data = self.get_historical_data()
        if historical_data:
            self.data_buffer.extend(historical_data)
            self.save_data()
        
        try:
            while True:
                try:
                    readings = self.get_current_readings()
                    self.add_to_buffer(readings)
                    self.logger.debug(f"Collected readings: {readings}")
                except Exception as e:
                    self.logger.error(f"Error in data collection cycle: {e}")
                
                time.sleep(polling_interval)
                
        except KeyboardInterrupt:
            self.logger.info("Data collection stopped by user")
            # Save any remaining data
            if self.data_buffer:
                self.save_data()


def ensure_dependencies():
    """Ensure all dependencies are installed using uv."""
    print("Installing dependencies with uv...")
    
    # Get the root directory of the project
    script_path = Path(__file__).resolve()
    root_dir = script_path.parent
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


def interactive_config(config_path: str):
    """
    Create a configuration file interactively.
    
    Args:
        config_path: Path where the configuration file will be saved.
    """
    # Import here for lazy loading
    import aranet4
    
    print("Aranet4 Interactive Configuration Mode")
    print("=====================================")
    
    # Start with default configuration
    config = {
        'device': {
            'mac_address': None
        },
        'data_collection': {
            'polling_interval': 300,
            'collect': {
                'co2': True,
                'temperature': True,
                'humidity': True,
                'pressure': True
            },
            'buffer_size': 10
        },
        'storage': {
            'data_dir': '../data',
            'file_format': 'csv',
            'file_pattern': 'aranet4_data_{date}.{format}',
            'daily_files': True
        },
        'logging': {
            'level': 'INFO',
            'file': '../logs/aranet_data_saver.log'
        }
    }
    
    # Scan for devices
    print("\nScanning for Aranet4 devices...")
    devices = []
    
    # This callback will be called for each device found
    def on_device_found(advertisement):
        if advertisement.device and advertisement.device.name and "Aranet" in advertisement.device.name:
            devices.append({
                'name': advertisement.device.name,
                'address': advertisement.device.address,
                'rssi': advertisement.rssi,
                'readings': advertisement.readings
            })
    
    try:
        # Start scanning
        aranet4.client.find_nearby(on_device_found, duration=5)
    except Exception as e:
        print(f"Error scanning for devices: {e}")
        print("This may happen if your system doesn't support Bluetooth scanning")
        print("or if you don't have necessary permissions.")
        devices = []
    
    if not devices:
        print("No Aranet4 devices found. Please make sure your devices are nearby and powered on.")
        print("You will need to enter the MAC address manually.")
        mac_address = input("\nEnter your Aranet4 device MAC address (XX:XX:XX:XX:XX:XX): ")
        config['device']['mac_address'] = mac_address
    else:
        # Display found devices
        print(f"\nFound {len(devices)} Aranet devices:")
        for i, device in enumerate(devices):
            name = device['name'] or "Unknown"
            address = device['address']
            rssi = device['rssi'] or "N/A"
            print(f"{i+1}. {name} ({address}) - Signal: {rssi} dBm")
        
        # Let user select a device
        while True:
            try:
                selection = input("\nSelect a device (enter number, or 'm' to enter MAC manually): ")
                if selection.lower() == 'm':
                    mac_address = input("Enter your Aranet4 device MAC address (XX:XX:XX:XX:XX:XX): ")
                    config['device']['mac_address'] = mac_address
                    break
                else:
                    idx = int(selection) - 1
                    if 0 <= idx < len(devices):
                        config['device']['mac_address'] = devices[idx]['address']
                        print(f"Selected: {devices[idx]['name']} ({devices[idx]['address']})")
                        break
                    else:
                        print("Invalid selection. Please try again.")
            except ValueError:
                print("Invalid input. Please enter a number or 'm'.")
    
    # Configure polling interval
    while True:
        try:
            interval = input(f"\nEnter polling interval in seconds [default: {config['data_collection']['polling_interval']}]: ")
            if interval.strip():
                interval = int(interval)
                if interval < 10:
                    print("Polling interval must be at least 10 seconds.")
                else:
                    config['data_collection']['polling_interval'] = interval
                    break
            else:
                break
        except ValueError:
            print("Invalid input. Please enter a number.")
    
    # Configure data collection options
    print("\nData collection options:")
    for param in ['co2', 'temperature', 'humidity', 'pressure']:
        while True:
            choice = input(f"Collect {param} data? (y/n) [default: y]: ").lower()
            if choice in ['y', 'yes', '']:
                config['data_collection']['collect'][param] = True
                break
            elif choice in ['n', 'no']:
                config['data_collection']['collect'][param] = False
                break
            else:
                print("Invalid input. Please enter 'y' or 'n'.")
    
    # Configure storage format
    while True:
        format_choice = input("\nChoose storage format (csv/json) [default: csv]: ").lower()
        if format_choice in ['csv', '']:
            config['storage']['file_format'] = 'csv'
            break
        elif format_choice == 'json':
            config['storage']['file_format'] = 'json'
            break
        else:
            print("Invalid choice. Please enter 'csv' or 'json'.")
    
    # Configure logging level
    print("\nLogging level options:")
    log_levels = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']
    for i, level in enumerate(log_levels):
        print(f"{i+1}. {level}")
    
    while True:
        try:
            log_choice = input(f"Choose logging level [default: INFO]: ")
            if not log_choice.strip():
                break
            else:
                idx = int(log_choice) - 1
                if 0 <= idx < len(log_levels):
                    config['logging']['level'] = log_levels[idx]
                    break
                else:
                    print("Invalid selection. Please try again.")
        except ValueError:
            print("Invalid input. Please enter a number.")
    
    # Save the configuration
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    
    print(f"\nConfiguration saved to {config_path}")
    print("You can now run the data saver with:")
    print(f"  python aranet_data_saver.py {config_path}")
    
    return config


def main():
    """Main entry point."""
    # Get the directory where this script is located
    script_path = Path(__file__).resolve()
    root_dir = script_path.parent
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Aranet4 Data Saver")
    parser.add_argument(
        "--config", "-c",
        help="Path to config file (default: config/local_config.yaml)",
        default=os.path.join(root_dir, "config", "local_config.yaml")
    )
    parser.add_argument(
        "config_path", 
        nargs="?", 
        help="Path to configuration file (positional argument, overrides --config)"
    )
    parser.add_argument(
        "--install", "-i",
        action="store_true",
        help="Install dependencies before running"
    )
    parser.add_argument(
        "--historical", "--historical-only", "-H",
        action="store_true",
        help="Only fetch historical data and exit"
    )
    parser.add_argument(
        "--configure", "-C",
        action="store_true",
        help="Run interactive configuration wizard"
    )
    args = parser.parse_args()
    
    # Install dependencies if requested
    if args.install:
        if not ensure_dependencies():
            sys.exit(1)
    
    # Determine config path (positional overrides --config)
    config_path = args.config_path if args.config_path else args.config
    
    # Run interactive configuration if requested
    if args.configure:
        try:
            import aranet4
        except ImportError:
            print("The aranet4 module is required for configuration.")
            print("Please install dependencies first with --install")
            sys.exit(1)
            
        interactive_config(config_path)
        sys.exit(0)
        
    # Create local config from template if it doesn't exist
    if not os.path.exists(config_path):
        template_path = os.path.join(os.path.dirname(config_path), 'config_template.yaml')
        if os.path.exists(template_path):
            import shutil
            print(f"No configuration file found at {config_path}.")
            print("You can either:")
            print("1. Create a configuration file from the template")
            print("2. Run the interactive configuration wizard")
            choice = input("\nEnter your choice (1/2): ")
            
            if choice == "2":
                try:
                    import aranet4
                except ImportError:
                    print("The aranet4 module is required for configuration.")
                    print("Please install dependencies first with --install")
                    sys.exit(1)
                    
                interactive_config(config_path)
            else:
                shutil.copy(template_path, config_path)
                print(f"Created local configuration file at {config_path} from template.")
                print("Please edit this file to configure your Aranet4 device before running again.")
            
            sys.exit(0)
    
    try:
        import aranet4
    except ImportError:
        print("The aranet4 module is required to run the data saver.")
        print("Please install dependencies first with --install")
        sys.exit(1)
        
    data_saver = Aranet4DataSaver(config_path)
    
    if args.historical:
        # Only collect historical data and exit
        historical_data = data_saver.get_historical_data()
        if historical_data:
            data_saver.data_buffer.extend(historical_data)
            data_saver.save_data()
        print(f"Downloaded and saved {len(historical_data)} historical records")
    else:
        # Run the continuous monitoring
        data_saver.run()


if __name__ == "__main__":
    main()