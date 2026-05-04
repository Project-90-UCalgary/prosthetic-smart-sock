ESP32 sketches for P90 mux + WiFi JSON endpoints.

Before flashing: edit YOUR_* placeholders in the .ino files for SSID and password.
See repo root README.md for project context.

Included:
- P90ArduinoMux.ino — multiplexer scan + SoftAP + HTTP /c1-c4 (mux ch 1–4)
- ESP32_Wifi_Station_Test.ino — STA + SoftAP fallback + diagnostics
