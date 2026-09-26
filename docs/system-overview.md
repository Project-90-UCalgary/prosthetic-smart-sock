# System overview

The prototype has four main parts:

1. A wearable sock with 16 force-sensitive resistor locations.
2. Multiplexing electronics that scan the sensors.
3. An ESP32 that collects readings and transmits them over a local Wi-Fi connection.
4. A MATLAB interface that displays live values, time histories, and a spatial sensor-response map.

```text
sensor sock -> multiplexing electronics -> ESP32 -> local Wi-Fi -> visualization
```

The current display demonstrates the acquisition and visualization workflow. Its values are best interpreted as relative sensor response until each channel has been calibrated under representative mounting and loading conditions.

## Intended workflow

The proposed workflow is to apply and zero the sock, record a standardized standing or walking task, review spatial and temporal loading patterns, and compare repeated measurements after a socket adjustment.

This remains an engineering research workflow. It is not intended to diagnose injury or replace clinical judgment.
