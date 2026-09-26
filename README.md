# Prosthetic Smart Sock

Project 90 is developing a low-cost sensor sock for transtibial prosthetic sockets. The prototype uses force-sensitive resistors to measure loading at selected locations inside the socket and sends the readings wirelessly to a live visualization interface.

The goal is to give prosthetists an additional source of information when evaluating socket fit. This is a research prototype, not a clinical or diagnostic device.

## Current prototype

- 16 sensing locations distributed around the sock
- multiplexed data acquisition with an ESP32
- local Wi-Fi transmission
- live MATLAB visualization with channel values, time histories, and a spatial map
- recording and replay for comparing benchtop sessions

The sensing, acquisition, wireless transmission, and visualization pipeline has been demonstrated on the bench. The sensors still require individual calibration, repeatability testing, and validation under representative loading. No human-participant or clinical validation is reported here.

## Repository scope

This public repository contains project documentation, approved figures, posters, and presentations. Firmware, analysis code, editable hardware designs, raw data, and internal development records are maintained privately while the research and publication status is reviewed.

- [System overview](docs/system-overview.md)
- [Project status](docs/project-status.md)
- [Publication notes](docs/publication-notes.md)
- [Posters](posters/README.md)
- [Presentations](presentations/README.md)

## Team

The poster materials identify the project team as A. W. Qureshi, N. Alam, H. Tariq, K. Chen, and A. Wong, with the Schulich School of Engineering at the University of Calgary, Calgary Sensor Lab, Project 90, and Cascade Prosthetic Services Ltd.

## Use and limitations

Sixteen discrete sensors cannot measure the full socket interface, and force-sensitive resistors are affected by hysteresis, drift, curvature, shear, temperature, and sensor-to-sensor variability. Results should be treated as prototype measurements until calibration and validation are complete.

No license has been assigned yet. Unless a license is added, the contents remain under their existing copyright.
