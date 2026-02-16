# WaveControlApp
> Mobile app for gesture-controlled IoT via MQTT and IR

---

## Overview

WaveControlApp is a Flutter application that provides a mobile interface to
monitor and control connected devices using MQTT. It pairs with a wearable
gesture system and a base station to manage smart devices and IR equipment.

This app is designed for:
- Smart home control
- Device monitoring
- MQTT-based integrations (e.g., Home Assistant)

---

## System Architecture

The system is composed of three main components:

### 1. Gesture Wristband
- Wearable motion device (IMU)
- Gesture recognition (TinyML or rule-based)

### 2. Base Station
- MQTT broker / Wi-Fi access point
- IR blaster for legacy devices

### 3. Mobile App (this repo)
- Flutter UI for control and monitoring
- MQTT configuration and status
- Notifications and history

### Communication
- Wi-Fi
- MQTT
- IR

---

## Features

- MQTT connection and reconnection
- Device monitoring and control
- Infrared device management
- Gesture-based actions (via wristband topics)
- Battery status monitoring
- Notification settings

---

## Project Structure

The app follows a simple layered structure to separate UI, state, and MQTT logic.

- lib/main.dart: App entry point, theme setup, and root navigation.
- lib/models/: Data models used across the app (device state, config items, history).
- lib/screens/: UI pages (home, configuration, monitoring, settings, IR screens).
- lib/services/: Business logic and integrations (MQTT, settings, device state sync).
- lib/theme/: Colors, typography, and UI theme definitions.
- lib/widgets/: Reusable UI components shared by multiple screens.

---

## Build and Run

### Requirements

- Flutter SDK
- Android Studio or VS Code with Flutter extension

### Commands

```bash
flutter pub get
flutter run
```

---

## MQTT Communication

### Flow

1. App connects to the broker using saved settings.
2. App subscribes to home/# and specific device state topics.
3. App sends a discovery request and receives the device list.
4. Incoming messages update device state, history, and notifications.

### Example topics

home/matter/request
home/matter/response
home/wristband/power
home/remote/

Payload examples:

```json
{"bat_lvl": 69, "sect": false}
```

---

## Main Screens

- Home: global status, quick access to control and monitoring.
- Configuration: assign gestures to actions and devices.
- Monitoring: live device states and bracelet status.
- IR configuration: create and manage IR remotes.
- Settings: MQTT, theme, language, notifications.
- Splash: app bootstrap and initial checks.

---

## MQTT Configuration

Connection settings are managed in the Settings screen and persisted locally.
The app automatically reconnects when network connectivity is restored.

Settings stored:
- server
- port
- username
- password

---

## Notifications

Notification settings let you enable or disable:
- success notifications (actions sent, items created)
- error notifications (MQTT errors, validation errors)
- learning notifications (IR learning and pairing)

---

## IR and Remotes

The app supports IR devices through:
- remote creation
- action creation
- learning flow (capture IR commands)
- per-device actions linked to gestures

---

## History and Logs

The app keeps a local history of outgoing and incoming MQTT messages.
Recent messages are used by monitoring screens and troubleshooting views.

History includes:
- topic
- payload
- timestamp
- direction (incoming/outgoing)
- success or error state

---

## Testing

```bash
flutter test
```
