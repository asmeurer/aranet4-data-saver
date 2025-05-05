#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.6"
# dependencies = ["flask", "pandas"]
# ///

"""
Aranet4 Data Visualizer

A web application to visualize data collected by the Aranet4 Data Saver.

Usage:
  ./aranet_visualizer.py [options]
  python -m aranet_visualizer [options]

Options:
  --data-dir PATH, -d PATH  Directory containing data files (default: data)
  --port NUMBER, -p NUMBER  Port to run the server on (default: 5000)
  --host ADDRESS            Host to run the server on (default: 127.0.0.1)
  --debug                   Enable debug mode with verbose logging
  --help, -h                Show this help message and exit
"""

import os
import csv
import json
import glob
import sys
import argparse
import logging
import pandas as pd
import subprocess
from datetime import datetime
from pathlib import Path
from flask import Flask, render_template, jsonify, request

def ensure_dependencies():
    """Ensure all dependencies are installed using uv."""
    print("Installing dependencies with uv...")
    
    # Get the root directory of the project
    script_path = Path(__file__).resolve()
    root_dir = script_path.parent
    
    try:
        # Run uv pip install with inline dependencies from script header
        result = subprocess.run(
            ["uv", "pip", "install", "flask", "pandas"],
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

# Set up logging - will configure level based on args
def setup_logging(debug=False):
    """Set up logging with appropriate level based on debug flag."""
    level = logging.DEBUG if debug else logging.INFO
    logging.basicConfig(level=level, 
                        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    return logging.getLogger('aranet_visualizer')

app = Flask(__name__, template_folder="templates", static_folder="static")

def find_data_files(data_dir="data"):
    """Find all CSV data files in the given directory."""
    # Ensure data directory exists
    logger.debug(f"Looking for data files in directory: {data_dir}")
    if not os.path.exists(data_dir):
        logger.warning(f"Data directory does not exist: {data_dir}")
        return []
    
    # Get all CSV files
    csv_files = glob.glob(os.path.join(data_dir, "*.csv"))
    logger.debug(f"Found CSV files: {csv_files}")
    
    # Get all JSON files 
    json_files = glob.glob(os.path.join(data_dir, "*.json"))
    logger.debug(f"Found JSON files: {json_files}")
    
    # Combine and sort by modification time (newest first)
    all_files = sorted(csv_files + json_files, 
                      key=lambda x: os.path.getmtime(x), 
                      reverse=True)
    
    logger.debug(f"Returning sorted files: {all_files}")
    return all_files

def load_data(file_path):
    """Load data from CSV or JSON file into pandas DataFrame."""
    logger.debug(f"Loading data from file: {file_path}")
    
    try:
        if file_path.endswith('.csv'):
            # Read CSV with more explicit parameters to handle potential issues
            df = pd.read_csv(
                file_path,
                parse_dates=['timestamp'],
                infer_datetime_format=True,
                dtype={
                    'co2': 'float64',
                    'temperature': 'float64',
                    'humidity': 'float64',
                    'pressure': 'float64'
                },
                on_bad_lines='skip'  # Skip lines with too many fields (pandas 1.3+)
            )
            logger.debug(f"Successfully loaded CSV with shape {df.shape}")
            return df
        elif file_path.endswith('.json'):
            with open(file_path, 'r') as f:
                data = json.load(f)
            df = pd.DataFrame(data)
            logger.debug(f"Successfully loaded JSON with shape {df.shape}")
            return df
        else:
            raise ValueError(f"Unsupported file format: {file_path}")
    except Exception as e:
        logger.exception(f"Error loading data from {file_path}: {e}")
        raise

def process_data(df):
    """Process the data for visualization."""
    logger.debug(f"Processing data with columns: {df.columns.tolist()}")
    
    # Convert timestamp to datetime if it's not already
    if not pd.api.types.is_datetime64_any_dtype(df['timestamp']):
        logger.debug("Converting timestamp column to datetime")
        df['timestamp'] = pd.to_datetime(df['timestamp'], errors='coerce')
    
    # Drop rows with invalid timestamps
    invalid_timestamps = df['timestamp'].isna().sum()
    if invalid_timestamps > 0:
        logger.warning(f"Dropping {invalid_timestamps} rows with invalid timestamps")
        df = df.dropna(subset=['timestamp'])
    
    # Sort by timestamp
    df = df.sort_values('timestamp')
    
    # Make sure numeric columns are numeric
    numeric_columns = ['co2', 'temperature', 'humidity', 'pressure']
    for col in numeric_columns:
        if col in df.columns:
            before_count = df[col].count()
            df[col] = pd.to_numeric(df[col], errors='coerce')
            after_count = df[col].count()
            if before_count != after_count:
                logger.warning(f"Converted {before_count-after_count} non-numeric values to NaN in column '{col}'")
    
    # Drop rows with all NaN values in the data columns
    present_numeric_cols = [col for col in numeric_columns if col in df.columns]
    if present_numeric_cols:
        na_before = len(df)
        df = df.dropna(subset=present_numeric_cols, how='all')
        na_after = len(df)
        if na_before != na_after:
            logger.warning(f"Dropped {na_before-na_after} rows with all NaN values in data columns")
    
    logger.debug(f"Processed data shape: {df.shape}")
    return df

def get_chart_data(df):
    """Convert DataFrame to format suitable for Chart.js individual charts."""
    if df.empty:
        logger.warning("Empty DataFrame provided to get_chart_data")
        return {}
    
    # Metric definitions with colors and display properties
    metrics = {
        'co2': {
            'color': 'rgb(255, 99, 132)',
            'label': 'CO2 (ppm)',
            'unit': 'ppm'
        },
        'temperature': {
            'color': 'rgb(255, 159, 64)',
            'label': 'Temperature (°C)',
            'unit': '°C'
        },
        'humidity': {
            'color': 'rgb(54, 162, 235)',
            'label': 'Humidity (%)',
            'unit': '%'
        },
        'pressure': {
            'color': 'rgb(75, 192, 192)',
            'label': 'Pressure (hPa)',
            'unit': 'hPa'
        }
    }
    
    # Create separate chart data for each metric
    chart_data = {}
    
    for metric_key, metric_info in metrics.items():
        if metric_key in df.columns:
            # Create data points in format Chart.js time series needs
            data_points = []
            for i, row in df.iterrows():
                # Only add points if the value is not NaN
                if pd.notna(row[metric_key]):
                    data_points.append({
                        'x': row['timestamp'].strftime('%Y-%m-%d %H:%M:%S'),
                        'y': float(row[metric_key])
                    })
            
            # Create a dataset for this metric
            dataset = {
                'label': metric_info['label'],
                'data': data_points,
                'borderColor': metric_info['color'],
                'backgroundColor': metric_info['color'].replace('rgb', 'rgba').replace(')', ', 0.1)'),
                'fill': True,
                'tension': 0.4,
                'pointRadius': 1,  # Smaller points for better performance
                'borderWidth': 2
            }
            
            # Create chart data structure
            chart_data[metric_key] = {
                'datasets': [dataset],
                'metric_info': metric_info
            }
            
            logger.debug(f"Created chart data for {metric_key} with {len(data_points)} data points")
    
    return chart_data

@app.route('/')
def index():
    """Render the main page."""
    data_dir = app.config.get('DATA_DIR', 'data')
    return render_template('index.html', data_dir=data_dir)

@app.route('/api/files')
def get_files():
    """API endpoint to get list of data files."""
    data_dir = app.config.get('DATA_DIR', 'data')
    logger.debug(f"API /api/files called, using data_dir: {data_dir}")
    files = find_data_files(data_dir)
    # Convert to relative paths for the frontend
    relative_files = [os.path.basename(f) for f in files]
    logger.debug(f"Returning relative file paths: {relative_files}")
    return jsonify(relative_files)

@app.route('/api/data')
def get_data():
    """API endpoint to get data for visualization."""
    data_dir = app.config.get('DATA_DIR', 'data')
    file_name = request.args.get('file')
    
    logger.debug(f"API /api/data called, file_name: {file_name}, data_dir: {data_dir}")
    
    if not file_name:
        # If no file specified, use the most recent one
        files = find_data_files(data_dir)
        if not files:
            logger.warning("No data files found")
            return jsonify({'error': 'No data files found'})
        file_path = files[0]
        logger.debug(f"No file specified, using most recent: {file_path}")
    else:
        file_path = os.path.join(data_dir, file_name)
        logger.debug(f"Using specified file: {file_path}")
        if not os.path.exists(file_path):
            logger.warning(f"File not found: {file_path}")
            return jsonify({'error': f'File not found: {file_path}'})
    
    try:
        logger.debug(f"Loading data from: {file_path}")
        df = load_data(file_path)
        logger.debug(f"Data loaded, shape: {df.shape}")
        logger.debug(f"DataFrame columns: {df.columns.tolist()}")
        
        df = process_data(df)
        logger.debug(f"Data processed, shape: {df.shape}")
        
        chart_data = get_chart_data(df)
        logger.debug(f"Chart data created")
        
        # Get basic stats
        stats = {}
        for col in ['co2', 'temperature', 'humidity', 'pressure']:
            if col in df.columns:
                stats[col] = {
                    'min': float(df[col].min()),
                    'max': float(df[col].max()),
                    'avg': float(df[col].mean()),
                    'current': float(df[col].iloc[-1])
                }
        
        response_data = {
            'chart_data': chart_data,
            'stats': stats,
            'file': os.path.basename(file_path),
            'timestamp_range': {
                'start': df['timestamp'].min().strftime('%Y-%m-%d %H:%M:%S'),
                'end': df['timestamp'].max().strftime('%Y-%m-%d %H:%M:%S')
            }
        }
        logger.debug(f"Returning response with stats for columns: {list(stats.keys())}")
        return jsonify(response_data)
    except Exception as e:
        logger.exception(f"Error processing data: {e}")
        return jsonify({'error': str(e)})

def main():
    """Run the app with parsed arguments."""
    parser = argparse.ArgumentParser(description="Aranet4 Data Visualizer")
    parser.add_argument("--data-dir", "-d", 
                       help="Directory containing the data files (default: data)",
                       default="data")
    parser.add_argument("--port", "-p", 
                       help="Port to run the server on (default: 5000)",
                       type=int, 
                       default=5000)
    parser.add_argument("--host", 
                       help="Host to run the server on (default: 127.0.0.1)",
                       default="127.0.0.1")
    parser.add_argument("--debug",
                       help="Enable debug mode with verbose logging",
                       action="store_true")
    parser.add_argument("--install",
                       help="Install dependencies before running",
                       action="store_true")
    args = parser.parse_args()
    
    # If install flag is used, ensure dependencies are installed
    if args.install and not ensure_dependencies():
        sys.exit(1)
    
    # Initialize logger with appropriate level
    global logger
    logger = setup_logging(args.debug)
    
    # Set up app configuration
    app.config['DATA_DIR'] = args.data_dir
    
    # Ensure data directory exists
    os.makedirs(args.data_dir, exist_ok=True)
    
    # Ensure template and static directories exist
    script_dir = Path(__file__).resolve().parent
    template_dir = script_dir / "templates"
    
    if not template_dir.exists():
        logger.error(f"Template directory not found: {template_dir}")
        print(f"Error: Template directory not found at {template_dir}")
        print("The visualization app requires template files to be present.")
        sys.exit(1)
    
    # Set Flask environment variables for debugging if needed
    if args.debug:
        os.environ['FLASK_DEBUG'] = '1'
        os.environ['FLASK_ENV'] = 'development'
        os.environ['PYTHONUNBUFFERED'] = '1'
        flask_debug = True
    else:
        flask_debug = False
    
    print(f"Starting Aranet4 Data Visualizer")
    print(f"Data directory: {args.data_dir}")
    print(f"Server running at http://{args.host}:{args.port}")
    print(f"Debug mode: {'ENABLED' if args.debug else 'DISABLED'}")
    print("\nPress Ctrl+C to stop the server\n")
    
    try:
        app.run(host=args.host, port=args.port, debug=flask_debug)
    except KeyboardInterrupt:
        print("\nServer stopped by user")
    except Exception as e:
        logger.error(f"Error running server: {e}")
        print(f"Error running server: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # When running directly with UV, dependencies should already be handled
    # or when running with --install flag
    main()