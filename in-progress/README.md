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

Add a new table row (`<tr>…</tr>`) when you land a batch of weekday changes: copy the previous row, then edit the **Week & dates** and **Highlights** cells.

<!-- Two columns: left col width via colgroup (tune first % if GitHub layout shifts). -->
<table width="100%">
<colgroup>
  <col width="55%">
  <col width="45%">
</colgroup>
<thead>
<tr>
<th align="left">Week &amp; dates</th>
<th align="left">Highlights</th>
</tr>
</thead>
<tbody>
<tr>
<td valign="top">

<strong>Week (Mon)</strong><br><code>2026-05-04</code><br><br>
<strong>Noted</strong><br><code>2026-05-04</code>

</td>
<td valign="top">

5 FSR channels; WiFi/JSON `c1`–`c5` + matching firmware; display 0–100; `turbo` colormap + linear heat scaling; 30 s history with **wall-clock** time axis; non-overlapping controls + more random-mode diversity; `in-progress/` split from mainline on GitHub.

</td>
</tr>
</tbody>
</table>
