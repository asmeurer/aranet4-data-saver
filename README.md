# Aranet4 Data Saver

A utility to regularly download and save data from Aranet4 air quality monitoring devices.

## Features

- Automatically collect current sensor readings at configurable intervals
- Download historical data from the device
- Configurable data collection (CO2, temperature, humidity, pressure)
- Save data in CSV or JSON format
- Run with UV for dependency management
- Configurable logging
- Interactive configuration wizard

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

## Project Structure

```
aranet-data-saver/
├── config/                 # Configuration files
│   ├── config_template.yaml  # Template configuration
│   └── local_config.yaml     # Your local configuration (git-ignored)
├── data/                   # Where data is stored
├── logs/                   # Log files
├── aranet_data_saver.py    # Unified script for all entry points
├── requirements.txt        # Python dependencies
└── README.md               # This file
```

## License

[MIT License](LICENSE)

## Credits

- Uses the [aranet4](https://github.com/Anrijs/Aranet4-Python) Python package by Anrijs