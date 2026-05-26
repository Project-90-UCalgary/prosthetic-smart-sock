# MindFuel Demo — Connection Tutorial

This guide walks through wiring the hardware, flashing ESP32 firmware, and connecting the MATLAB GUI. No prior experience with the full repo is required if you start from this folder.

## Parts list

- ESP32 development board (USB data cable)
- CD74HC4067 (16-channel analog multiplexer) breakout or IC + breadboard
- Up to 16 analog pressure sensors (or potentiometers for bench testing)
- Jumper wires, common ground
- Computer with **Arduino IDE** (ESP32 board support) and **MATLAB**

## Step 1 — Understand the signal path

```
Sensor (c0..c15) → MUX common (SIG) → ESP32 ADC (GPIO 34)
ESP32 GPIO 2,12,14,27,26 → MUX EN, S0, S1, S2, S3
ESP32 → Wi‑Fi JSON  OR  USB serial  →  MATLAB GUI
```

Each mux channel is selected in turn; the ESP32 reads one ADC value per channel and sends all 16 to MATLAB.

## Step 2 — Wire the multiplexer

Use the pin map from the included firmware (both WiFi and Serial sketches):

| Signal | ESP32 GPIO | MUX pin (typical breakout label) |
|--------|------------|----------------------------------|
| Enable | **2** | EN |
| Select S0 | **12** | S0 |
| Select S1 | **14** | S1 |
| Select S2 | **27** | S2 |
| Select S3 | **26** | S3 |
| Analog in | **34** | SIG (common output) |

Additional wiring:

- **VCC** — 3.3 V from ESP32 (or 5 V if your mux/sensors require it; keep ADC within ESP32 limits).
- **GND** — common ground between ESP32, mux, and all sensors.
- **Sensor outputs** — one sensor per mux channel **C0–C15** (sometimes labeled Y0–Y15 on breakouts).

Optional status LED (WiFi sketch only): **GPIO 4** → LED → resistor → GND.

> **Tip:** GPIO 34 is input-only and on ADC1, which works while Wi‑Fi is active on ESP32.

### Bench test without real sensors

Connect each mux channel to a **potentiometer** (wiper → channel, ends → 3.3 V and GND) or leave channels floating to verify the GUI responds.

## Step 3 — Choose firmware path

### Option A — WiFi (best for live demos)

1. Open `firmware/ESP32_Wifi_Station_Test/ESP32_Wifi_Station_Test.ino` in Arduino IDE.
2. Edit credentials at the top of the file:
   ```cpp
   const char* WIFI_SSID = "YOUR_WIFI_SSID";
   const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
   ```
   SoftAP fallback (if STA fails):
   ```cpp
   const char* AP_SSID = "P90-ESP32-MUX";
   const char* AP_PASSWORD = "CHANGE_ME_AP_PASSWORD";
   ```
3. **Tools → Board** — select your ESP32 board.
4. **Tools → Port** — select the USB COM port.
5. **Upload** the sketch.
6. Open **Serial Monitor** at **115200 baud** and note the IP address printed at boot.

**Verify in a browser** (same network as ESP32, or connected to ESP32 SoftAP):

- Dashboard: `http://<esp32-ip>/`
- All channels JSON: `http://<esp32-ip>/mux-all`
- Status: `http://<esp32-ip>/status`

Example `/mux-all` response:
```json
{"c0":1234,"c1":1180,...,"c15":990}
```

### Option B — USB Serial

1. Open `firmware/ESP32_Serial_Mux_16ch/ESP32_Serial_Mux_16ch.ino`.
2. Upload to ESP32 (same board/port as above).
3. Serial output is **9600 baud**, one line per frame:
   ```
        1234  1180  1150 ... (16 six-character fields) 
   ```
4. Close Arduino Serial Monitor before opening MATLAB (only one program can use the COM port).

## Step 4 — Connect MATLAB

1. Open MATLAB.
2. Go to the demo MATLAB folder:
   ```matlab
   cd('MindFuel Demo/matlab')   % adjust path if needed
   runDemo
   ```
   Or run `MATLABWiFiV1` directly.

3. In the **Controls** panel, pick an **Input Mode**:

   | Mode | When to use |
   |------|-------------|
   | Random | No hardware — test charts and 3D heatmap |
   | Sliders | Manual demo — drag M0–M15 sliders |
   | Serial (c0–c15) | ESP32 running **ESP32_Serial_Mux_16ch** |
   | WiFi AP (/mux-all) | ESP32 running **ESP32_Wifi_Station_Test** |

### WiFi mode setup

1. If ESP32 uses **SoftAP**, connect your PC to the ESP32 Wi‑Fi network (`P90-ESP32-MUX` by default).
2. In `MATLABWiFiV1.m`, set `WIFI_URL` near the top to match your ESP32:
   ```matlab
   WIFI_URL = "http://192.168.4.1/mux-all";   % typical SoftAP address
   ```
   For station mode, use the IP from Serial Monitor, e.g. `"http://192.168.1.42/mux-all"`.
3. Select **WiFi AP (/mux-all)** in the GUI dropdown.

### Serial mode setup

1. Flash **ESP32_Serial_Mux_16ch**.
2. In the GUI, select **Serial (c0–c15)**.
3. Choose the correct **COM port** (click **Refresh ports** if needed).
4. Close Arduino Serial Monitor if the port is busy.

## Step 5 — Confirm it is working

You should see:

- **Live Values** bars moving for M0–M15.
- **History** lines updating over the last 10 seconds.
- **3D heatmap** on the leg model with colored blobs near active sensors.
- Sensor labels **M0–M15** on the mesh surface.

Press a sensor (or turn a test potentiometer): the corresponding bar and heat spot should rise. With default settings, **more pressure → higher bar value** (ADC is inverted in software).

## Troubleshooting

| Problem | Things to check |
|---------|-----------------|
| No WiFi connection | SSID/password, 2.4 GHz network, Serial Monitor boot log |
| Browser can't reach `/mux-all` | PC on same network (or on ESP32 SoftAP); correct IP |
| MATLAB WiFi mode flatlines | `WIFI_URL` matches ESP32 IP; test URL in browser first |
| Serial mode no data | Correct COM port; 9600 baud sketch; Serial Monitor closed |
| Values inverted | Toggle `SERIAL_INVERT_ADC` in `MATLABWiFiV1.m` |
| Wrong channel order | Mux S0–S3 wiring; sensor on expected Cn pin |
| Port access denied | Close Arduino IDE Serial Monitor and other serial tools |

## Demo tips (MindFuel / presentation)

1. Start in **Random** or **Sliders** mode to show the GUI before plugging in hardware.
2. Switch to **WiFi** for a cable-free demo — audience can also open the ESP32 dashboard on a phone.
3. Rotate the 3D leg with **left-click drag** on the heatmap panel.
4. Adjust **Smoothing (EMA α)** if live traces look too noisy or too sluggish.

## Next steps

- Per-sensor calibration: edit `CAL_ADC_MIN` and `CAL_ADC_MAX` in `MATLABWiFiV1.m`.
- Reshuffle sensor positions on the mesh: change `SENSOR_SEED`.
- Replace geometry: overwrite `matlab/models/leg.stl`.

For repository-wide context, see the root [README.md](../README.md) and [SETUP.md](../SETUP.md).
