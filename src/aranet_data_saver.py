#!/usr/bin/env python3
"""
Aranet4 Data Saver

This script regularly polls an Aranet4 device for sensor data and saves it to disk.
"""

import os
import sys
import time
import logging
import datetime
import json
import csv
import yaml
import aranet4
from pathlib import Path
from typing import Dict, List, Any, Optional


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
            for entry in history:
                record = {
                    'timestamp': entry.timestamp.isoformat(),
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


def main():
    """Main entry point."""
    # Parse command line arguments
    import argparse
    parser = argparse.ArgumentParser(description="Aranet4 Data Saver")
    parser.add_argument("config_path", nargs="?", help="Path to configuration file")
    parser.add_argument("--historical-only", action="store_true", help="Only collect historical data and exit")
    args = parser.parse_args()
    
    # Determine config path
    if args.config_path:
        config_path = args.config_path
    else:
        # Default config location
        config_path = os.path.join(os.path.dirname(__file__), '..', 'config', 'local_config.yaml')
        
        # Create local config from template if it doesn't exist
        if not os.path.exists(config_path):
            template_path = os.path.join(os.path.dirname(config_path), 'config_template.yaml')
            if os.path.exists(template_path):
                import shutil
                shutil.copy(template_path, config_path)
                print(f"Created local configuration file at {config_path} from template.")
                print("Please edit this file to configure your Aranet4 device before running again.")
                sys.exit(0)
    
    data_saver = Aranet4DataSaver(config_path)
    
    if args.historical_only:
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