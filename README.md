# prosthetic-smart-sock
Creating a smart sock for lower limb prosthetics to create more comfortable and constant fitting

## MATLAB 3D model

Run `MATLABWiFiV1.m` for the live GUI. The limb model is your CAD STL (`models/leg.stl`) with **16 sensors** on the calf sock patch. Change `SENSOR_SEED` to reshuffle sensor sites; replace `models/leg.stl` to update geometry.

## MindFuel Demo

See **`MindFuel Demo/`** for a self-contained demo package (ESP32 firmware, MATLAB GUI, wiring tutorial, and `models/leg.stl`).

## Setup

See `SETUP.md` for full replication steps (hardware, firmware, and MATLAB workflow).
