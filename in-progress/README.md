# In-progress (weekday work — not yet team-reviewed)

This folder holds **work-in-progress** versions of the GUI and ESP32 firmware. The **same paths at the repository root** and under `firmware/` stay on the **mainline / Saturday baseline** the team already agreed on.

| Path (mirrors repo) | Notes |
|----------------------|--------|
| `P90_Simulated_MLAB.m` | Weekday iteration: 5ch, 30s history, wall-clock axis, etc. |
| `ESP32_Wifi_Station_Test.ino` | Station + SoftAP + `/c1-c5` and related |
| `firmware/P90ArduinoMux.ino` | AP mode + serial + JSON |
| `firmware/ESP32_Wifi_Station_Test.ino` | |
| `firmware/README.txt` | |

**How to use:** Copy or diff these files over the root copies when promoting after Saturday sign-off, or run MATLAB/Arduino from this folder path until then.

**Do not** treat this tree as the default for new contributors — use root + `firmware/` for the stable project layout until the team merges the WIP.

## Weekly update log (in-progress)

GitHub’s README renderer usually **ignores** `<colgroup>` / `%` widths on HTML tables, so a two-column “Week & dates | Highlights” layout stays squeezed on the left. This section uses **headings + bullets** instead so dates stay on one line.

When you add a week: copy the `### …` block below, change the dates, and edit the highlights.

### Mon `2026-05-04`

**Highlights**

5 FSR channels; WiFi/JSON `c1`–`c5` + matching firmware; display 0–100; `turbo` colormap + linear heat scaling; 30 s history with **wall-clock** time axis; non-overlapping controls + more random-mode diversity; `in-progress/` split from mainline on GitHub.
