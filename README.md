# Aranet4 Data Saver & Visualizer

A utility to download, save, and visualize data from Aranet4 air quality monitoring devices.

## Features

### Data Collection

- Automatically collect current sensor readings at configurable intervals
- Download historical data from the device
- Configurable data collection (CO2, temperature, humidity, pressure)
- Save data in CSV or JSON format
- Run with UV for dependency management
- Configurable logging
- Interactive configuration wizard

### Data Visualization

- Web-based dashboard to visualize your Aranet4 data
- Separate interactive time-series charts for each measurement type:
  - CO2 levels (ppm)
  - Temperature (°C)
  - Humidity (%)
  - Pressure (hPa)
- **Interactive zoom and pan functionality** on all charts:
  - Zoom in/out on time axis using the mouse wheel or pinch gestures
  - Pan through time by dragging the chart
  - Reset zoom with dedicated buttons
- Statistics display for each metric (min, max, average, current)
- Support for both CSV and JSON data files
- File selection dropdown to view different data files
- Responsive design that works on desktop and mobile devices

## Requirements

- Python 3.6+
- An Aranet4 device with "Smart Home integrations" enabled in the Aranet Home mobile app
- UV package manager (optional, but recommended)

## Installation

1. Clone this repository:
   ```
   git clone <repository-url>
   cd aranet-data-saver
   ```

2. Install dependencies with UV:
   ```
   ./aranet_data_saver.py --install
   ```

   Or with pip:
   ```
   pip install -r requirements.txt
   ```

## Configuration

Two ways to configure:

1. Interactive configuration wizard:
   ```
   ./aranet_data_saver.py --configure
   ```
   This will scan for nearby devices and guide you through the setup process.

2. Manual configuration:
   ```
   cp config/config_template.yaml config/local_config.yaml
   ```
   Then edit `config/local_config.yaml` with your device settings.

Configuration example:
```yaml
# Device settings
device:
  # MAC address of your Aranet4 device (format: XX:XX:XX:XX:XX:XX)
  mac_address: "XX:XX:XX:XX:XX:XX"

# Data collection settings
data_collection:
  # How often to poll the device for new data (in seconds)
  polling_interval: 300  # 5 minutes

# ... other settings
```

## Usage

Run the script:

```
./aranet_data_saver.py [options]
```

Or using Python:

```
python aranet_data_saver.py [options]
```

### Command Line Options

```
./aranet_data_saver.py --help
```

Options:
- `-c, --config PATH`: Specify a custom configuration file path
- `-i, --install`: Install dependencies before running
- `-H, --historical`: Only fetch historical data and exit
- `-C, --configure`: Run interactive configuration wizard

### Examples

Only fetch historical data and exit:
```
./aranet_data_saver.py --historical
```

Use a specific configuration file:
```
./aranet_data_saver.py --config /path/to/my/config.yaml
```

## Data Storage

By default, data is stored in the `data/` directory in CSV format. The filename format and other storage options can be configured in the configuration file.

## Data Visualization

### Installation

No separate installation is needed! The visualizer script uses `uv` for dependency management, just like the data collection script.

### Running the Visualizer

Run the visualizer directly:

```bash
./aranet_visualizer.py
```

Or using Python:

```bash
python aranet_visualizer.py
```

Or with `uv`:

```bash
uv run aranet_visualizer.py
```

Then open your web browser and navigate to: http://127.0.0.1:5000

### Visualizer Command Line Options

- `--data-dir`, `-d`: Directory containing the data files (default: `data`)
- `--port`, `-p`: Port to run the server on (default: `5000`)
- `--host`: Host to run the server on (default: `127.0.0.1`)
- `--debug`: Enable debug mode with verbose logging (useful for troubleshooting)
- `--install`: Install dependencies explicitly (normally handled automatically by uv)

Examples:

```bash
# Basic usage with default settings
./aranet_visualizer.py

# Explicitly install dependencies and run
./aranet_visualizer.py --install

# Use a custom data directory
./aranet_visualizer.py --data-dir /path/to/your/data

# Change port and enable debug mode
./aranet_visualizer.py --port 8080 --debug
```

### Interactive Features

The visualizer includes powerful interactive features:

1. **Zooming**:
   - Use the mouse wheel to zoom in and out on the time axis
   - On touch devices, use pinch gestures to zoom
   - Zoom charts individually to focus on specific time periods

2. **Panning**:
   - Click and drag to pan through time when zoomed in
   - Explore different time ranges with smooth navigation

3. **Reset**:
   - Click the "Reset Zoom" button to return to the original view
   - Each chart has its own reset button

### Use Cases

The interactive chart functionality enables multiple analysis scenarios:

1. **Daily Patterns Analysis**:
   - Compare CO2 levels against temperature throughout the day
   - Spot correlations between different environmental factors
   - Identify patterns in specific time windows by zooming in

2. **Long-term Trend Analysis**:
   - Use larger data files to analyze trends over weeks or months
   - Identify seasonal or occupancy-based patterns

3. **Anomaly Detection**:
   - Quickly identify unusual spikes or drops in readings
   - Zoom in to investigate anomalies in detail
   - Compare anomalies across different metrics simultaneously

4. **Data Validation**:
   - Compare readings from multiple days by switching data files
   - Verify sensor consistency and reliability
   - Investigate potential measurement errors

## Project Structure

```
aranet-data-saver/
├── config/                   # Configuration files
│   ├── config_template.yaml  # Template configuration
│   └── local_config.yaml     # Your local configuration (git-ignored)
├── data/                     # Where data is stored
├── logs/                     # Log files
├── templates/                # HTML templates for visualization
│   └── index.html            # Main visualization dashboard template
├── aranet_data_saver.py      # Data collection script
├── aranet_visualizer.py      # Data visualization web app (uses uv for dependencies)
├── requirements.txt          # Python dependencies for data collection
└── README.md                 # This file
```

## License

[MIT License](LICENSE)

## Credits

- Uses the [aranet4](https://github.com/Anrijs/Aranet4-Python) Python package by Anrijs
