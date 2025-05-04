# Aranet4 Data Saver

A utility to regularly download and save data from Aranet4 air quality monitoring devices.

## Features

- Automatically collect current sensor readings at configurable intervals
- Download historical data from the device
- Configurable data collection (CO2, temperature, humidity, pressure)
- Save data in CSV or JSON format
- Run with UV for dependency management
- Configurable logging

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
   ./run.py --install
   ```

   Or with pip:
   ```
   pip install -r requirements.txt
   ```

## Configuration

1. Create your configuration file by copying the template:
   ```
   cp config/config_template.yaml config/local_config.yaml
   ```

2. Edit `config/local_config.yaml` and configure the settings:
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

### Basic Usage

Run the script with UV:

```
./run.py
```

This will:
1. Use the configuration from `config/local_config.yaml`
2. Download historical data from the device
3. Start polling for new readings at the configured interval

### Command Line Options

```
./run.py --help
```

Options:
- `-c, --config PATH`: Specify a custom configuration file path
- `-i, --install`: Install dependencies before running
- `-H, --historical`: Only fetch historical data and exit

### Run Directly

You can also run the script directly:

```
./src/aranet_data_saver.py [CONFIG_PATH] [--historical-only]
```

## Data Storage

By default, data is stored in the `data/` directory in CSV format. The filename format and other storage options can be configured in the configuration file.

## Development

### Project Structure

```
aranet-data-saver/
├── config/                 # Configuration files
│   ├── config_template.yaml  # Template configuration
│   └── local_config.yaml     # Your local configuration (git-ignored)
├── data/                   # Where data is stored
├── logs/                   # Log files
├── src/                    # Source code
│   └── aranet_data_saver.py  # Main script
├── run.py                  # UV runner script
├── requirements.txt        # Python dependencies
└── README.md               # This file
```

## License

[MIT License](LICENSE)

## Credits

- Uses the [aranet4](https://github.com/Anrijs/Aranet4-Python) Python package by Anrijs