function prosthetic_paraboloid_gui
% prosthetic_paraboloid_gui.m
% 16-channel prosthetic visualization (mux c0–c15):
% - Limb surface: CAD STL (models/leg.stl), thigh / knee / calf assembly
% - 16 fixed sensor sites along lower leg (tip -> below knee)
% - Live bars + rolling history
% - 3D heatmap with 16 sensor points
% - GUI sliders + mode toggle (Random / Sliders / Serial / WiFi AP)
% - Serial: 4_16_mux sketch — sprintf("%%6d") per index; all 16 mux channels
%   Hardware: higher pressure -> lower ADC; SERIAL_INVERT_ADC maps to "higher = more pressure"
% - WiFi AP: ESP32 /mux-all JSON (c0–c15)
% - Rotate limb with left-click dragging (rotate3d)

clearvars; close all; clc;

%% ================= SETTINGS =================
NCH = 16;
N_SENSORS_3D = 16;
SENSOR_SEED = 42; % reproducible random sites on calf patch; change to reshuffle
LIMB_STL = fullfile(fileparts(mfilename('fullpath')), 'models', 'leg.stl');
SIGMA_HEAT_MM = 20;   % Gaussian spread on STL mesh (mm) — larger = wider heat blobs
HEAT_GAMMA = 1.0;     % linear display: max sensor values can reach the top of the colorbar
LABELS = "M" + string(0:NCH-1);
LABELS_SERIAL = LABELS;
LABELS_3D = LABELS;

SAMPLE_HZ  = 50;
DT         = 1 / SAMPLE_HZ;
WINDOW_SEC = 10;
maxlen     = round(SAMPLE_HZ * WINDOW_SEC);

YMIN = 0;
YMAX = 50;             % display 0..50 (higher = more pressure after optional invert)
ADC_IN_MAX = 4095;     % ESP32 default analogRead full scale (12-bit)
% Circuit wiring: more mechanical pressure -> lower ADC (typical FSR / divider setup).
% SERIAL_INVERT_ADC maps ADC so the GUI still shows higher values for more pressure.
SERIAL_INVERT_ADC = true;
USE_PER_SENSOR_CAL = true;
% Per-sensor calibration ranges for raw ADC (c0..c15).
% Start with full range, then replace with measured per-channel min/max.
CAL_ADC_MIN = 500 * ones(1, NCH);
CAL_ADC_MAX = ADC_IN_MAX * ones(1, NCH);

ALPHA = 0.15;          % EMA smoothing for bars/history only (heatmap uses raw)
sigma = SIGMA_HEAT_MM; % heat spread radius on STL vertices (mm)

%% ================= STATE =================
t_sim = 0;
ema = zeros(NCH,1);
buf = zeros(NCH, maxlen);
x_hist = linspace(-WINDOW_SEC, 0, maxlen);

% Mode: 1=Random, 2=Sliders, 3=Serial, 4=WiFi AP
mode = 1;

% Slider values storage (0..YMAX)
sliderVals = 25 * ones(NCH,1);

% Serial: 16 × sprintf("%6d", A0) -> 96 chars per line (no A1 field)
serialHandle = [];           % serialport object, empty when closed
lastSerialRaw = zeros(NCH,1); % hold last good frame if a read fails
serialLineAccum = char([]);  % bytes until LF (avoids readline timeout warnings)
BYTES_PER_CH = 6;           % fixed width per mux channel (%6d)
N_MUX_CH = 16;

% WiFi source (ESP32 SoftAP)
WIFI_URL = "http://192.168.4.1/mux-all";
lastWifiRaw = zeros(NCH,1); % hold last good frame if a read fails

%% ================= BUILD LIMB (CAD STL + 16 sensors on calf patch) =================
[V, F, ~, ~, s_x, s_y, s_z, limbMeta] = loadProstheticStlMesh( ...
    LIMB_STL, N_SENSORS_3D, SENSOR_SEED);
heat_v = zeros(size(V, 1), 1);
limbBeige = [0.86 0.80 0.68];

%% ================= FIGURE + LAYOUT =================
% Dark theme palette (panels/plots) + light "ink" for text/axes.
uiBg   = [0.07 0.08 0.10];
plotBg = uiBg;                     % keep panels and plots flush
ink    = [0.94 0.95 0.97];
ctlBg  = [0.96 0.96 0.98];         % light background for sliders/popups/buttons
ctlFg  = [0.10 0.10 0.12];         % dark text on light controls
gridCol = [0.55 0.57 0.62];        % visible grid on dark bg

fig = figure('Color', uiBg, 'Name', 'Prosthetic Smart Sock Telemetry', ...
    'NumberTitle', 'off', 'Position', [40 40 1320 760]);
set(fig, 'DefaultAxesColor', uiBg);
set(fig, 'DefaultTextColor', ink);
set(fig, 'DefaultAxesXColor', ink);
set(fig, 'DefaultAxesYColor', ink);
set(fig, 'DefaultAxesZColor', ink);

% Plots (left) + wider control column (right) for 16 sliders
main = uipanel(fig, 'Units', 'normalized', 'Position', [0 0 0.70 1], ...
    'BorderType', 'none', 'BackgroundColor', uiBg);
ctrl = uipanel(fig, 'Units', 'normalized', 'Position', [0.70 0 0.30 1], ...
    'Title', 'Controls', 'BackgroundColor', plotBg, 'ForegroundColor', ink);

% Layout [left, bottom, width, height] — 3D on right; room below for horizontal colorbar
posBar = [0.05 0.54 0.44 0.40];
posHist = [0.05 0.08 0.44 0.40];
pos3D = [0.58 0.36 0.32 0.40];
posCb = [0.62 0.11 0.28 0.05];

% ---- 3D first (back layer) so bar/history draw on top and hide stray 3D ticks ----
ax3D = axes(main, 'Position', pos3D);
hold(ax3D, 'on');
hLimbBase = trisurf(F, V(:, 1), V(:, 2), V(:, 3), ...
    'FaceColor', limbBeige, 'EdgeColor', 'none', 'FaceAlpha', 1.0, ...
    'AmbientStrength', 0.65, 'DiffuseStrength', 0.45, ...
    'SpecularStrength', 0.0, 'BackFaceLighting', 'unlit');
hSurf = trisurf(F, V(:, 1), V(:, 2), V(:, 3), heat_v, ...
    'EdgeColor', 'none', 'FaceColor', 'interp', 'FaceAlpha', 0.55, ...
    'AmbientStrength', 0.70, 'DiffuseStrength', 0.40, ...
    'SpecularStrength', 0.0, 'BackFaceLighting', 'unlit');
hold(ax3D, 'off');
style3DAxes(ax3D, ink, plotBg);
axis(ax3D, 'vis3d');
apply3DViewBounds(ax3D, V, 0.15);
ax3D.Clipping = 'on';
if isprop(ax3D, 'ClippingStyle')
    ax3D.ClippingStyle = '3dbox';
end
xlabel(ax3D, 'X (mm)'); ylabel(ax3D, 'Y (mm)'); zlabel(ax3D, 'Z (mm)');
[~, stlName, ~] = fileparts(limbMeta.stlPath);
title(ax3D, sprintf('3D Heatmap — %s (%d sensors, seed %d)', ...
    stlName, limbMeta.nSensors, limbMeta.sensorSeed));
view(ax3D, 135, 22); % native CAD export orientation
% Soft fill light only (no headlight) — eliminates the bright streaks
% on the truncated open top of the thigh.
light(ax3D, 'Style', 'infinite', 'Position', [0.3 0.4 1.0], 'Color', [0.85 0.85 0.9]);
lighting(ax3D, 'gouraud');
material(ax3D, 'dull');
colormap(ax3D, hot);
cb = colorbar(ax3D, 'southoutside');
cb.Label.String = 'Intensity (0..100)';
styleColorbar(cb, main, plotBg, ink, posCb);

hold(ax3D,'on');
hPts = scatter3(ax3D, s_x, s_y, s_z, 72, zeros(N_SENSORS_3D, 1), 'filled', ...
    'MarkerEdgeColor', [0.9 0.9 0.95]);
for i = 1:N_SENSORS_3D
    text(ax3D, s_x(i) * 1.04, s_y(i) * 1.04, s_z(i), LABELS_3D(i), ...
        'FontSize', 8, 'FontWeight', 'bold', 'Color', ink);
end
hold(ax3D,'off');
apply3DPosition(ax3D, pos3D);
syncUiBackground(fig, main, ctrl, uiBg);

% ---- Live Bars (front layer) ----
axBar = axes(main, 'Position', posBar);
styleChartAxes(axBar, plotBg, ink);
b = bar(axBar, 1:NCH, zeros(1, NCH), 'FaceColor', [0.36 0.62 0.95], 'EdgeColor', 'none');
ylim(axBar, [YMIN YMAX]);
xticks(axBar, 1:NCH);
xticklabels(axBar, LABELS);
xtickangle(axBar, 45);
ylabel(axBar, 'Level (0–50)');
title(axBar, 'Live Values');
grid(axBar, 'on');
axBar.Color = plotBg;

% ---- History (front layer) ----
axHist = axes(main, 'Position', posHist);
styleChartAxes(axHist, plotBg, ink);
hold(axHist, 'on');
hLine = gobjects(NCH, 1);
histColors = lines(NCH);
for i = 1:NCH
    hLine(i) = plot(axHist, x_hist, buf(i, :), 'LineWidth', 1.4, ...
        'Color', histColors(i, :));
end
hold(axHist, 'off');
xlim(axHist, [-WINDOW_SEC 0]);
ylim(axHist, [YMIN YMAX]);
xlabel(axHist, 'Time (s) [0 = now]');
ylabel(axHist, 'Level (0–50)');
title(axHist, sprintf('History (last %ds)', WINDOW_SEC));
legend(axHist, LABELS, 'Location', 'northeast', 'NumColumns', 2, ...
    'FontSize', 7, 'TextColor', ink, 'Color', plotBg, 'EdgeColor', gridCol);
grid(axHist, 'on');
axHist.Color = plotBg;
syncUiBackground(fig, main, ctrl, uiBg);
apply3DPosition(ax3D, pos3D);
styleColorbar(cb, main, plotBg, ink, posCb);

% Rotate only the 3D axes (not the whole figure)
rot = rotate3d(ax3D);
rot.Enable = 'on';

%% ================= CONTROLS =================
% Mode selector
uicontrol(ctrl, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.08 0.93 0.84 0.04], ...
    'String', 'Input Mode', 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'BackgroundColor', plotBg, 'ForegroundColor', ink);

modePopup = uicontrol(ctrl, 'Style','popupmenu', 'Units','normalized', ...
    'Position',[0.08 0.89 0.84 0.045], ...
    'String', {'Random', 'Sliders', 'Serial (c0–c15)', 'WiFi AP (/mux-all)'}, ...
    'Value', 1, ...
    'BackgroundColor', ctlBg, 'ForegroundColor', ctlFg, ...
    'Callback', @onModeChanged);

uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 0.845 0.84 0.03], ...
    'String','COM port (Serial mode)', 'HorizontalAlignment','left', ...
    'BackgroundColor', plotBg, 'ForegroundColor', ink);

[portListCell, portPick] = serialPortListForUi();
comPortPopup = uicontrol(ctrl, 'Style','popupmenu', 'Units','normalized', ...
    'Position',[0.08 0.798 0.52 0.038], ...
    'String', portListCell, ...
    'Value', min(portPick, numel(portListCell)), ...
    'BackgroundColor', ctlBg, 'ForegroundColor', ctlFg, ...
    'Tooltip', 'Refresh after plugging USB. Pick the same COM as Arduino IDE. Close Serial Monitor first. COM1–COM20 appears if MATLAB lists no ports.');

uicontrol(ctrl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[0.62 0.798 0.30 0.038], ...
    'String', 'Refresh ports', ...
    'BackgroundColor', ctlBg, 'ForegroundColor', ctlFg, ...
    'Callback', @onRefreshSerialPorts);

% Smoothing slider (optional, nice)
uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 0.76 0.84 0.035], ...
    'String','Smoothing (EMA α)', 'HorizontalAlignment','left', ...
    'BackgroundColor', plotBg, 'ForegroundColor', ink);

alphaSlider = uicontrol(ctrl, 'Style','slider', 'Units','normalized', ...
    'Position',[0.08 0.73 0.84 0.03], ...
    'Min', 0.01, 'Max', 1.0, 'Value', ALPHA, ...
    'BackgroundColor', ctlBg, 'ForegroundColor', ctlFg, ...
    'Callback', @onAlphaChanged);

alphaReadout = uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 0.695 0.84 0.03], ...
    'String', sprintf('α = %.2f', ALPHA), ...
    'HorizontalAlignment','left', ...
    'BackgroundColor', plotBg, 'ForegroundColor', ink);

% Sliders: two columns (M0–M7, M8–M15) with readable row height
sliderPanel = uipanel(ctrl, 'Units', 'normalized', ...
    'Position', [0.03 0.08 0.94 0.58], 'Title', 'Channel levels (Sliders mode)', ...
    'BackgroundColor', plotBg, 'ForegroundColor', ink, 'BorderType', 'line');
sliderHandles = gobjects(NCH, 1);
valueTexts = gobjects(NCH, 1);

colX = [0.04, 0.52];
sliderW = 0.38;
yTop = 0.94;
rowH = 0.105;

for i = 1:NCH
    if i <= 8
        col = 1;
        row = i;
    else
        col = 2;
        row = i - 8;
    end
    x = colX(col);
    y = yTop - row * rowH;

    uicontrol(sliderPanel, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [x, y, 0.10, 0.05], 'String', LABELS(i), ...
        'BackgroundColor', plotBg, 'ForegroundColor', ink, 'HorizontalAlignment', 'left');

    sliderHandles(i) = uicontrol(sliderPanel, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [x + 0.11, y - 0.012, sliderW, 0.042], ...
        'Min', YMIN, 'Max', YMAX, 'Value', sliderVals(i), ...
        'SliderStep', [1 / (YMAX - YMIN), 5 / (YMAX - YMIN)], ...
        'BackgroundColor', ctlBg, 'ForegroundColor', ctlFg, ...
        'Callback', @(src, evt) onSliderChanged(i, src));

    valueTexts(i) = uicontrol(sliderPanel, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [x + sliderW + 0.12, y, 0.08, 0.05], ...
        'String', sprintf('%d', round(sliderVals(i))), ...
        'BackgroundColor', plotBg, 'ForegroundColor', ink, 'HorizontalAlignment', 'right');
end

uicontrol(ctrl, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.08 0.02 0.84 0.05], ...
    'String', "Tip: Drag the 3D plot with LEFT mouse to rotate.", ...
    'HorizontalAlignment', 'left', 'BackgroundColor', plotBg, 'ForegroundColor', ink);

%% ================= TIMER LOOP (NON-BLOCKING GUI) =================
tmr = timer( ...
    'ExecutionMode','fixedRate', ...
    'Period', DT, ...
    'TimerFcn', @tick);

% Make sure timer stops when figure closes
fig.CloseRequestFcn = @onClose;

start(tmr);

%% ================= CALLBACKS =================
    function onRefreshSerialPorts(~, ~)
        prev = '';
        items = comPortPopup.String;
        vi = comPortPopup.Value;
        if iscell(items) && vi >= 1 && vi <= numel(items)
            prev = items{vi};
        end
        [cells, pick] = serialPortListForUi();
        comPortPopup.String = cells;
        comPortPopup.Value = min(max(1, pick), numel(cells));
        if strlength(strtrim(prev)) > 0 && ~startsWith(strtrim(prev), '(')
            k = find(strcmpi(cells, prev), 1);
            if ~isempty(k)
                comPortPopup.Value = k;
            end
        end
    end

    function onModeChanged(~, ~)
        prev = mode;
        mode = modePopup.Value; % 1 random, 2 sliders, 3 serial, 4 wifi
        if mode == 3 && prev ~= 3
            openSerialPort();
        elseif mode ~= 3 && prev == 3
            closeSerialPort();
        end
        if mode == 3 || mode == 4
            xticklabels(axBar, LABELS_SERIAL);
            legend(axHist, LABELS_SERIAL, 'Location', 'northeast', ...
                'NumColumns', 2, 'FontSize', 7, ...
                'TextColor', ink, 'Color', plotBg, 'EdgeColor', gridCol);
        else
            xticklabels(axBar, LABELS);
            legend(axHist, LABELS, 'Location', 'northeast', ...
                'NumColumns', 2, 'FontSize', 7, ...
                'TextColor', ink, 'Color', plotBg, 'EdgeColor', gridCol);
        end
    end

    function onSliderChanged(idx, src)
        sliderVals(idx) = src.Value;
        valueTexts(idx).String = sprintf('%d', round(sliderVals(idx)));
    end

    function onAlphaChanged(src, ~)
        ALPHA = src.Value;
        alphaReadout.String = sprintf('α = %.2f', ALPHA);
    end

    function tick(~, ~)
        if ~isvalid(fig) || ~isvalid(b) || ~isvalid(hSurf) || ~isvalid(hLimbBase)
            return;
        end

        % ---- Generate inputs ----
        if mode == 1
            raw = makeRandomSignals(t_sim);
        elseif mode == 2
            raw = sliderVals; % 0..YMAX
        elseif mode == 3
            raw = readMuxAllSerial(); % Serial: 16 × %6d per line
        else
            raw = readWifiMuxAll(); % WiFi AP JSON c0–c15
        end

        % ---- EMA smoothing (bars/history only; heatmap follows raw for instant release) ----
        for k = 1:NCH
            ema(k) = ema(k) + ALPHA * (raw(k) - ema(k));
        end
        v = ema;

        % ---- Update rolling buffer ----
        buf(:,1:end-1) = buf(:,2:end);
        buf(:,end) = v;

        % ---- Update bars + history ----
        b.YData = buf(:,end)';  % bar wants row vector

        for k = 1:NCH
            hLine(k).YData = buf(k,:);
        end

        % ---- Heat field: raw ADC, local blobs that preserve each sensor's peak color ----
        intensityHeat = 100 * (raw - YMIN) / max(eps, (YMAX - YMIN));
        intensityHeat = max(0, min(100, intensityHeat));

        heat_v(:) = 0;
        for k = 1:NCH
            d2 = (V(:, 1) - s_x(k)).^2 + (V(:, 2) - s_y(k)).^2 + (V(:, 3) - s_z(k)).^2;
            sensorHeat = intensityHeat(k) .* exp(-d2 / (2 * sigma^2));
            heat_v = max(heat_v, sensorHeat);
        end
        heat_v = min(100, heat_v);
        heatShow = 100 * (heat_v / 100) .^ HEAT_GAMMA;

        hSurf.CData = heatShow;
        hPts.CData  = intensityHeat; % match instantaneous heat (same as surface drive)
        set(ax3D, 'CLim', [0 100]); % fixed scale so cooling shows immediately

        t_sim = t_sim + DT;
        drawnow limitrate;
    end

    function raw = makeRandomSignals(t)
        % Smooth-ish values 0..YMAX for all 16 mux channels
        raw = zeros(NCH, 1);
        for k = 1:NCH
            f1 = 0.08 + 0.015 * k;
            f2 = 0.22 + 0.01 * mod(k, 5);
            ph = 0.55 * k;
            raw(k) = 24 + 14 * sin(2 * pi * f1 * t + ph) + 6 * sin(2 * pi * f2 * t + 0.3 * k);
        end
        raw = raw + randn(NCH, 1) * 1.2;
        raw = max(YMIN, min(YMAX, raw));
    end

    function onClose(~, ~)
        closeSerialPort();
        try
            stop(tmr);
            delete(tmr);
        catch
        end
        delete(fig);
    end

    function openSerialPort()
        closeSerialPort();
        items = comPortPopup.String;
        vi = comPortPopup.Value;
        if iscell(items)
            portName = strtrim(items{min(max(1, vi), numel(items))});
        else
            portName = strtrim(items(min(max(1, vi), numel(items))));
        end
        if strlength(portName) == 0 || startsWith(portName, '(')
            warndlg(['No usable port selected. Plug in the Arduino, click Refresh ports, ' ...
                'then pick the board. Close the Arduino IDE Serial Monitor if it is open.'], 'Serial');
            return;
        end
        try
            serialHandle = serialport(portName, 9600);
            configureTerminator(serialHandle, "LF");
            serialHandle.Timeout = 1; % used only by blocking ops; we use read(count)
            serialLineAccum = char([]);
            flush(serialHandle);
        catch ME
            serialHandle = [];
            extra = '';
            try
                avail = serialportlist("available");
                if ~isempty(avail)
                    extra = sprintf(' Ports MATLAB sees: %s.', strjoin(cellstr(avail), ', '));
                else
                    extra = ' MATLAB reports no available serial ports.';
                end
            catch
            end
            warndlg([ME.message extra], 'Serial open failed');
        end
    end

    function closeSerialPort()
        if isempty(serialHandle)
            return;
        end
        try
            if isvalid(serialHandle)
                flush(serialHandle);
                delete(serialHandle);
            end
        catch
        end
        serialHandle = [];
        serialLineAccum = char([]);
    end

    function raw = readMuxAllSerial()
        % Arduino loop: sprintf(padded,"%%6d", analogRead(A0)) for i=0..15 -> 96-char line + LF.
        % GUI uses all mux indices c0..c15.
        % Circuit: more pressure -> lower ADC; SERIAL_INVERT_ADC flips before scaling to YMAX.
        % Assemble lines with read(n,uint8) so partial chunks do not trigger readline timeouts.
        raw = lastSerialRaw;
        if isempty(serialHandle) || ~isvalid(serialHandle)
            return;
        end
        try
            n = serialHandle.NumBytesAvailable;
            if n > 0
                chunk = read(serialHandle, n, "uint8");
                serialLineAccum = [serialLineAccum char(chunk)]; %#ok<AGROW>
            end

            needLen = N_MUX_CH * BYTES_PER_CH;
            while true
                ix = find(serialLineAccum == 10, 1, 'first'); % LF from Serial.println
                if isempty(ix)
                    break;
                end
                line = serialLineAccum(1:ix-1);
                serialLineAccum = serialLineAccum(ix+1:end);
                line(line == 13) = []; % drop CR if present
                % Do NOT strtrim the whole line — sprintf("%6d",...) pads with leading spaces;
                % trimming would shift columns and corrupt fixed-width fields.
                if numel(line) < needLen
                    continue;
                end
                line = line(1:needLen);
                mux1 = zeros(NCH, 1);
                for k = 1:NCH
                    off = (k - 1) * BYTES_PER_CH;
                    seg = line(off + (1:BYTES_PER_CH));
                    mux1(k) = str2double(strtrim(seg));
                end
                if any(isnan(mux1))
                    continue;
                end
                raw = mapAdcToDisplay(mux1);
                lastSerialRaw = raw;
            end

            if numel(serialLineAccum) > 8000
                serialLineAccum = serialLineAccum(end-3999:end);
            end
        catch
        end
    end

    function raw = readWifiMuxAll()
        % Poll ESP32 /mux-all JSON: c0..c15
        raw = lastWifiRaw;
        try
            resp = webread(char(WIFI_URL));
            if ischar(resp) || isstring(resp)
                resp = jsondecode(char(resp));
            end
            if ~isstruct(resp)
                return;
            end
            adc = zeros(NCH, 1);
            for k = 0:NCH-1
                key = sprintf('c%d', k);
                if ~isfield(resp, key)
                    return;
                end
                adc(k + 1) = double(resp.(key));
            end
            raw = mapAdcToDisplay(adc);
            lastWifiRaw = raw;
        catch
            % Keep last good frame on transient WiFi failures.
        end
    end

    function out = mapAdcToDisplay(adc)
        adc = double(adc(:));
        if USE_PER_SENSOR_CAL
            mn = CAL_ADC_MIN(:);
            mx = CAL_ADC_MAX(:);
            if numel(mn) ~= NCH || numel(mx) ~= NCH
                error('CAL_ADC_MIN/CAL_ADC_MAX must each have %d values.', NCH);
            end
            span = max(mx - mn, eps);
            normv = (adc - mn) ./ span;
        else
            normv = adc ./ max(ADC_IN_MAX, eps);
        end
        if SERIAL_INVERT_ADC
            normv = 1 - normv;
        end
        normv = max(0, min(1, normv));
        out = YMIN + normv * (YMAX - YMIN);
    end
end

function [cells, preferredIdx] = serialPortListForUi()
% Prefer ports MATLAB marks available, then "all", then COM1–COM20 so you can still try by hand.
preferredIdx = 1;
cells = {};

if exist('serialportlist', 'file') ~= 2
    cells = comPortsManualFallback();
    preferredIdx = min(5, numel(cells)); % default COM5
    return;
end

try
    pAvail = serialportlist("available");
catch
    pAvail = string.empty;
end
if ~isempty(pAvail)
    cells = cellstr(pAvail);
    preferredIdx = preferredComIndex(cells);
    return;
end

try
    pAll = serialportlist("all");
catch
    pAll = string.empty;
end
if ~isempty(pAll)
    cells = cellstr(pAll);
    preferredIdx = preferredComIndex(cells);
    return;
end

cells = comPortsManualFallback();
preferredIdx = min(5, numel(cells)); % default COM5
end

function cells = comPortsManualFallback()
cells = arrayfun(@(n) sprintf('COM%d', n), 1:20, 'UniformOutput', false);
end

function idx = preferredComIndex(cells)
k = find(strcmpi(cells, 'COM5'), 1);
if ~isempty(k)
    idx = k;
else
    idx = 1;
end
end

function styleChartAxes(ax, bg, ink)
ax.Color = bg;
ax.XColor = ink;
ax.YColor = ink;
ax.ZColor = ink;
ax.GridColor = [0.55 0.57 0.62];
ax.GridAlpha = 0.35;
ax.Title.Color = ink;
ax.Subtitle.Color = ink;
ax.XLabel.Color = ink;
ax.YLabel.Color = ink;
ax.ZLabel.Color = ink;
ax.FontSize = 10;
end

function style3DAxes(ax, ink, bg)
if nargin < 3
    bg = [0.07 0.08 0.10];
end
ax.Color = bg;
ax.XColor = ink;
ax.YColor = ink;
ax.ZColor = ink;
ax.GridColor = [0.55 0.57 0.62];
ax.GridAlpha = 0.30;
ax.Title.Color = ink;
ax.XLabel.Color = ink;
ax.YLabel.Color = ink;
ax.ZLabel.Color = ink;
ax.FontSize = 9;
ax.Box = 'on';
ax.LineWidth = 0.5;
ax.TickLength = [0.01 0.01];
if isprop(ax, 'SortMethod')
    ax.SortMethod = 'childorder';
end
end

function apply3DPosition(ax, pos)
% Lock 3D axes to a smaller box (do not expand with TightInset).
ax.Units = 'normalized';
ax.ActivePositionProperty = 'position';
ax.Position = pos;
ax.Layer = 'bottom';
end

function apply3DViewBounds(ax, V, padFrac)
% Use the STL's actual per-axis extents (not a cube) so the projected 3D box
% stays inside the axes rectangle instead of bulging into neighboring panels.
mins = min(V, [], 1);
maxs = max(V, [], 1);
ranges = maxs - mins;
center = (mins + maxs) / 2;
halfSpans = (ranges / 2) * (1 + padFrac);
xlim(ax, center(1) + halfSpans(1) * [-1 1]);
ylim(ax, center(2) + halfSpans(2) * [-1 1]);
zlim(ax, center(3) + halfSpans(3) * [-1 1]);
daspect(ax, [1 1 1]);
pbaspect(ax, [halfSpans(1) halfSpans(2) halfSpans(3)]);
end

function styleColorbar(cb, parentPanel, bg, ink, posCb)
% Horizontal intensity bar below the 3D axes (panel-normalized position).
cb.Location = 'manual';
try
    cb.Parent = parentPanel;
catch
    % Older MATLAB: keep default parent; position may be less exact
end
cb.Units = 'normalized';
cb.Position = posCb;
cb.Color = ink;
cb.XColor = ink;
cb.YColor = ink;
cb.Label.Color = ink;
cb.TickDirection = 'out';
cb.FontSize = 8;
cb.Limits = [0 100];
cb.Ticks = 0:25:100;
cb.TickLabels = string(cb.Ticks);
cb.Box = 'off';
if isprop(cb, 'AxisLocation')
    cb.AxisLocation = 'out';
end
if isprop(cb, 'Direction')
    cb.Direction = 'normal';
end
end

function syncUiBackground(fig, main, ctrl, bg)
set(fig, 'Color', bg);
set(main, 'BackgroundColor', bg);
set(ctrl, 'BackgroundColor', bg);
axList = findall(main, 'Type', 'axes');
for k = 1:numel(axList)
    axList(k).Color = bg;
end
cbList = findall(main, 'Type', 'colorbar');
for k = 1:numel(cbList)
    cbList(k).Color = bg;
end
end