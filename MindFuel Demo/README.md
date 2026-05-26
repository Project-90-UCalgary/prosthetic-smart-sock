# MindFuel Demo

Self-contained package for demonstrating the **Project 90 prosthetic smart sock** telemetry stack: 16-channel pressure sensing through a CD74HC4067 multiplexer, ESP32 firmware, and a MATLAB live visualization GUI with a 3D leg heatmap.

Part of the [prosthetic-smart-sock](https://github.com/Project-90-UCalgary/prosthetic-smart-sock) repository.

## What this iteration does

### Hardware

- **16 analog channels** (mux c0–c15) read through a **CD74HC4067** 16:1 analog multiplexer.
- **ESP32** selects mux channels, reads ADC values (12-bit, 0–4095), and exposes them to MATLAB.
- Typical sensor wiring: more mechanical pressure → **lower** ADC reading (FSR / divider style). The MATLAB GUI inverts this so **higher displayed values = more pressure**.

### Firmware (ESP32)

Two sketches are included under `firmware/`:

| Sketch | Use case |
|--------|----------|
| `ESP32_Wifi_Station_Test` | **Recommended for demos.** ESP32 joins Wi‑Fi (or starts SoftAP) and serves JSON at `/mux-all`. Built-in web dashboard at `/`. |
| `ESP32_Serial_Mux_16ch` | USB serial at **9600 baud** — one line per frame, 16 fixed-width ADC fields for MATLAB **Serial** mode. |

Both sketches share the same mux pin map (see `TUTORIAL.md`).

### MATLAB GUI (`matlab/MATLABWiFiV1.m`)

Run `runDemo` or `MATLABWiFiV1` from the `matlab/` folder.

The GUI provides:

- **3D heatmap** on a CAD leg mesh (`models/leg.stl`) with **16 sensor sites** on the calf/stump patch.
- **Live bar chart** and **10-second rolling history** for all 16 channels (M0–M15).
- **Dark theme** with light control sliders.
- **Four input modes:**
  1. **Random** — simulated signals for testing without hardware.
  2. **Sliders** — manual channel levels via on-screen sliders.
  3. **Serial** — live data from `ESP32_Serial_Mux_16ch` over USB.
  4. **WiFi AP (/mux-all)** — polls ESP32 JSON (default URL: `http://192.168.4.1/mux-all` when using SoftAP).

Heatmap behavior (current tuning):

- Local Gaussian blobs per sensor (`SIGMA_HEAT_MM = 20` mm).
- Max sensor value maps to the top of the color scale (yellow/white on the `hot` colormap).
- Fixed colorbar **0–100** with ticks at 0, 25, 50, 75, 100.

### Supporting files

| File | Role |
|------|------|
| `loadProstheticStlMesh.m` | Loads `leg.stl`, places 16 deterministic sensor sites along the stump axis. |
| `models/leg.stl` | Project 90 leg assembly mesh (mm units, native CAD orientation). |
| `runDemo.m` | Convenience launcher — changes to this folder and opens the GUI. |

## Quick start

1. Wire the mux and sensors (see **`TUTORIAL.md`**).
2. Flash **`firmware/ESP32_Wifi_Station_Test`** (set Wi‑Fi credentials or use SoftAP).
3. In MATLAB:
   ```matlab
   cd('MindFuel Demo/matlab')
   runDemo
   ```
4. Set **Input Mode** to **WiFi AP (/mux-all)** and confirm `WIFI_URL` in the script matches your ESP32 IP (e.g. `http://192.168.4.1/mux-all` for SoftAP).

For step-by-step wiring, flashing, and network setup, see **`TUTORIAL.md`**.

## Configuration knobs

In `MATLABWiFiV1.m` (top of file):

| Setting | Default | Purpose |
|---------|---------|---------|
| `WIFI_URL` | `http://192.168.4.1/mux-all` | ESP32 JSON endpoint |
| `SENSOR_SEED` | `42` | Reproducible sensor placement on the mesh |
| `SIGMA_HEAT_MM` | `20` | Heat blob radius on the 3D surface |
| `SERIAL_INVERT_ADC` | `true` | Map lower ADC → higher display value |
| `CAL_ADC_MIN` / `CAL_ADC_MAX` | per-channel | Optional per-sensor calibration |

## Security note

Do **not** commit real Wi‑Fi passwords. Use placeholders in firmware and share credentials privately for demos.
