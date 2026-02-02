# Bikes Virtual Locks

Flutter desktop application that simulates physical bike lock devices for AWS IoT. Used for development and testing of the bikes-api backend.

## Features

- Simulates multiple virtual bike locks
- Connects to AWS IoT Core via MQTT
- Receives unlock commands via IoT Shadow
- Reports lock state (locked, empty, clamps) back to IoT
- Timer-based auto-lock functionality
- Heartbeat reporting every 60 seconds

## Requirements

- Flutter SDK 3.9+
- macOS, Windows, or Linux
- AWS IoT device certificates

## Setup

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Place AWS CA certificate in `assets/ca/`:
   - Download from AWS IoT Console
   - Save as `AmazonRootCA1.pem`

3. Configure AWS IoT endpoint in the app settings

4. Import device certificates (generated via bikes-api provisioning)

## Running

```bash
# macOS
flutter run -d macos

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

## Architecture

```
lib/
├── app.dart                 # App root widget
├── main.dart                # Entry point
├── core/
│   ├── constants/           # App & AWS constants
│   └── utils/               # Logger, helpers
├── features/
│   ├── aws_config/          # AWS configuration
│   ├── certificates/        # Certificate management
│   ├── locks/               # Lock simulation
│   ├── settings/            # App settings
│   └── things/              # IoT Things management
└── services/
    ├── aws_iot_service.dart # AWS IoT API
    ├── connection_manager.dart # MQTT connections
    ├── mqtt_service.dart    # MQTT client
    └── storage_service.dart # Local storage
```

## Related Projects

- [bikes-api](../bikes-api) - Backend API and infrastructure
