# Project 90 Smart Sock Setup Guide

This guide explains how to set up the ESP32 firmware and MATLAB script so someone else can replicate the project.

## 1) Requirements

- ESP32 development board
- CD74HC4067 (16-channel analog multiplexer) or equivalent
- Pressure/analog sensors connected to the mux channels
- Jumper wires and breadboard
- USB cable for ESP32
- Arduino IDE (with ESP32 board support installed)
- MATLAB (for running the desktop-side script)
- A Wi-Fi network for STA mode (optional if using SoftAP fallback)

## 2) Wiring (based on current firmware constants)

The sketch `ESP32_Wifi_Station_Test.ino` currently uses:

- `LED_PIN = 4`
- `MUX_EN_PIN = 2`
- `MUX_S0_PIN = 12`
- `MUX_S1_PIN = 14`
- `MUX_S2_PIN = 27`
- `MUX_S3_PIN = 26`
- `MUX_SIG_PIN = 34` (ADC input)

Wire your mux select lines and signal output to these ESP32 pins, or update the constants in the sketch to match your hardware.

## 3) Configure and Flash ESP32 Firmware

1. Open `ESP32_Wifi_Station_Test.ino` in Arduino IDE.
2. Install required libraries if prompted (`WiFi.h` and `WebServer.h` come with ESP32 core).
3. Set network credentials before flashing:
   - `WIFI_SSID`
   - `WIFI_PASSWORD`
   - Optional AP fallback: `AP_SSID`, `AP_PASSWORD`
4. Select the correct ESP32 board and COM port.
5. Upload the sketch.
6. Open Serial Monitor at `115200` baud and confirm startup messages.

## 4) Validate ESP32 Server

After boot, the board will:

- Try to join Wi-Fi in station mode first.
- If station connection fails, start its own SoftAP network.

From a browser on the same network, open:

- `http://<esp32-ip>/` (dashboard)
- `http://<esp32-ip>/status`
- `http://<esp32-ip>/c0-c3`
- `http://<esp32-ip>/mux-all`

If using SoftAP fallback, connect your computer to the ESP32 AP SSID first, then use the AP IP shown in Serial Monitor.

## 5) Run MATLAB Integration

Primary script: **`MATLABWiFiV1.m`**

- 3D model: CAD assembly STL (`models/leg.stl`, copied from your export)
- **16 sensors** (mux c0–c15) placed randomly on the **calf sock patch** (mesh heuristic)
- Reshuffle sites: change `SENSOR_SEED` near the top of the script
- Replace mesh: overwrite `models/leg.stl` or set `LIMB_STL` in the script
- Loader: `loadProstheticStlMesh.m`

Legacy: `buildProstheticLimbMesh.m` (procedural fallback), `P90_Simulated_MLAB.m` (older GUI)

Typical workflow:

1. Open MATLAB and run `MATLABWiFiV1`.
2. Set `WIFI_URL` if using WiFi mode (ESP32 IP + `/mux-all`).
3. Confirm the 3D view shows 16 labeled points on the calf patch and live values update.

## 6) Security and Good Practices

- Do not commit real Wi-Fi passwords or personal hotspot credentials.
- Keep placeholders in committed code and share real credentials privately.
- If credentials were committed by mistake, rotate/change them immediately.

## 7) Troubleshooting

- No Wi-Fi connection:
  - Recheck SSID/password and signal strength.
  - Confirm 2.4 GHz support for ESP32 network.
- No sensor readings:
  - Verify mux wiring and ground reference.
  - Confirm `MUX_SIG_PIN` is connected to a valid ADC-capable pin.
- MATLAB cannot connect:
  - Confirm PC and ESP32 are on the same network.
  - Ping the ESP32 IP and test `/status` endpoint in browser first.
