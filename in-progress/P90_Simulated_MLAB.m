function prosthetic_paraboloid_gui
% prosthetic_paraboloid_gui.m
% Prosthetic visualization (NCH mux channels):
% - Limb surface: paraboloid cup + smooth cone + vertical cylinder
% - Live bars + rolling history
% - 3D heatmap with sensor points on the limb
% - GUI sliders + mode toggle (Random / Sliders / Serial / WiFi)
% - Serial: 16_6_mux sketch — sprintf("%%6d") per index; first NCH mux fields M0–M(N-1)
%   Hardware: higher pressure -> lower ADC; SERIAL_INVERT_ADC maps serial stream only
% - WiFi JSON /c1-cN: sensors S1–SN = mux c1–cN keys; WIFI_INVERT_ADC=false -> higher ADC -> higher bar
% - Rotate limb with left-click dragging (rotate3d)

clearvars; close all; clc;

%% ================= SETTINGS =================
NCH = 5; % first five mux channels (JSON / WiFi c1–c5)
LABELS = compose("FSR%d", 1:NCH);
LABELS_SERIAL = compose("M%d", 0:NCH-1);
LABELS_WIFI = compose("S%d", 1:NCH); % WiFi: map to JSON c1..cN (mux ch 1–N)
LABELS_3D = compose("FSR%d", 1:NCH);

SAMPLE_HZ  = 50;
DT         = 1 / SAMPLE_HZ;
WINDOW_SEC = 30;
% Ring buffer length: ~(WINDOW_SEC * SAMPLE_HZ) + 1 samples so oldest vs newest spans WINDOW_SEC at nominal DT.
maxlen = round(WINDOW_SEC * SAMPLE_HZ) + 1;

YMIN = 0;
YMAX = 100;            % display 0..100 (higher = more pressure after optional invert)
ADC_IN_MAX_SERIAL = 1023;  % legacy Arduino serial stream scale
ADC_IN_MAX_WIFI   = 4095;  % ESP32 ADC scale over WiFi endpoint
% Serial stream: more mechanical pressure -> lower ADC (typical FSR). Invert so bars rise with pressure.
SERIAL_INVERT_ADC = true;
% WiFi JSON: direct mapping — higher ADC (e.g. c1) -> higher GUI value (set true to mirror serial invert).
WIFI_INVERT_ADC = false;
% Extra gain on WiFi-only scaling so low ADC (~few hundred counts) uses more of 0..YMAX.
% (Tuned with YMAX=100; increase if bars look too small.)
WIFI_DISPLAY_GAIN = 5;

ALPHA = 0.15;          % EMA smoothing for bars/history only (heatmap uses raw)
sigma = 0.32;          % heat spread on limb (larger Z span than paraboloid-only)

% Limb geometry (model units): paraboloid cup + smooth cone + vertical cylinder
Rmax   = 1.0;          % paraboloid rim radius
H      = 1.5;          % paraboloid height (apex z=0, rim z=H)
shapeK = H/(Rmax^2);   % z = k*r^2 on paraboloid section
R_cyl  = Rmax;         % same radius as cone rim — no pinch at the join
h_cone = 0;            % no taper band; stem continues flush from rim
H_cyl  = 1.35;         % vertical cylinder height above paraboloid rim
Z_top  = H + h_cone + H_cyl;

%% ================= STATE =================
t_sim = 0;
ema = zeros(NCH,1);
buf = zeros(NCH, maxlen);
% Wall-clock time (toc from histWallTic) for each column — x-axis matches real duration (GUI often << SAMPLE_HZ).
t_hist_cols = nan(1, maxlen);

% Mode: 1=Random, 2=Sliders, 3=Serial, 4=WiFi
mode = 1;

% Slider values storage (0..YMAX)
sliderVals = 50 * ones(NCH,1);

% Serial: 16 × sprintf("%6d", A0) -> 96 chars per line (no A1 field)
serialHandle = [];           % serialport object, empty when closed
lastSerialRaw = zeros(NCH,1); % hold last good frame if a read fails
serialLineAccum = char([]);  % bytes until LF (avoids readline timeout warnings)
BYTES_PER_CH = 6;           % fixed width per mux channel (%6d)
N_MUX_CH = 16;

% WiFi source (ESP32 station first, SoftAP fallback) — JSON must include c1..cN
WIFI_URLS = ["http://172.20.10.2/c1-c5", "http://192.168.4.1/c1-c5"];
WIFI_POLL_HZ = 8;               % decouple HTTP polling from GUI timer
WIFI_TIMEOUT_SEC = 0.35;        % short timeout prevents GUI stalls
lastWifiRaw = zeros(NCH,1); % hold last good frame if a read fails
lastWifiPollTic = tic;
activeWifiUrlIdx = 1;           % stick to last known-good endpoint
wifiWebOpts = weboptions('Timeout', WIFI_TIMEOUT_SEC);

%% ================= BUILD LIMB SURFACE (paraboloid + cone + cylinder) =================
Nz = 130;
Ntheta = 180;
z_axis = linspace(0, Z_top, Nz);
th_axis = linspace(0, 2*pi, Ntheta);
[TH, ZZ] = meshgrid(th_axis, z_axis);

R_of_Z = limbRvec(ZZ, H, shapeK, Rmax, R_cyl, h_cone);
X = R_of_Z .* cos(TH);
Y = R_of_Z .* sin(TH);
Z = ZZ;

% Mux sites on the limb — same Z near the tip (low on cup), spread by angle
z_tip = 0.30 * H; % paraboloid band near apex
fsr_th = zeros(NCH, 1);
fsr_th(:) = (0:NCH-1).' * (2*pi/NCH) + 0.12;
z_fsr = zeros(NCH, 1);
z_fsr(:) = z_tip;
r_fsr = limbRvec(z_fsr, H, shapeK, Rmax, R_cyl, h_cone);
fsr_x = r_fsr .* cos(fsr_th);
fsr_y = r_fsr .* sin(fsr_th);
fsr_z = z_fsr;

%% ================= FIGURE + LAYOUT =================
fig = figure('Color','w', 'Name','Paraboloid Prosthetic Telemetry', ...
    'NumberTitle','off', 'Position',[80 80 1200 720]);

% Use tiledlayout for plots, and a side panel for controls
main = uipanel(fig, 'Units','normalized', 'Position',[0 0 0.78 1], 'BorderType','none');
ctrl = uipanel(fig, 'Units','normalized', 'Position',[0.78 0 0.22 1], 'Title','Controls');

t = tiledlayout(main, 2, 2, 'Padding','compact', 'TileSpacing','compact');

% ---- Live Bars ----
axBar = nexttile(t, 1);
b = bar(axBar, 1:NCH, zeros(1,NCH));
ylim(axBar, [YMIN YMAX]);
xticks(axBar, 1:NCH);
xticklabels(axBar, LABELS);
ylabel(axBar, 'Level (0–100)');
title(axBar, 'Live Values');
grid(axBar, 'on');

% ---- History ----
axHist = nexttile(t, 3);
hold(axHist,'on');
hLine = gobjects(NCH,1);
for i=1:NCH
    hLine(i) = plot(axHist, linspace(-WINDOW_SEC, 0, maxlen), buf(i,:), 'LineWidth', 1.2);
end
hold(axHist,'off');
axHist.XLimMode = 'manual';
xlim(axHist, [-WINDOW_SEC 0]); % fixed horizontal span [−WINDOW_SEC, 0]
ylim(axHist, [YMIN YMAX]);
xlabel(axHist, 'Time (s) [0 = now, wall clock]');
ylabel(axHist, 'Level (0–100)');
title(axHist, sprintf('History (last %ds)', WINDOW_SEC));
legend(axHist, LABELS, 'Location','northwest');
grid(axHist, 'on');

% ---- 3D Paraboloid Heatmap ----
ax3D = nexttile(t, [2 1]);
heat0 = zeros(size(Z));
hSurf = surf(ax3D, X, Y, Z, heat0, 'EdgeColor','none');
axis(ax3D,'equal'); axis(ax3D,'tight');
xlabel(ax3D,'X'); ylabel(ax3D,'Y'); zlabel(ax3D,'Z');
title(ax3D,'3D Heatmap (limb: cup + cone + stem)');
view(ax3D, 40, 25);
camlight(ax3D, 'headlight');
lighting(ax3D, 'gouraud');
% turbo spreads mid–high values better than hot; parula if turbo unavailable
try
    colormap(ax3D, turbo(256));
catch
    colormap(ax3D, parula(256));
end
cb = colorbar(ax3D);
cb.Label.String = 'Intensity (0–100)';

hold(ax3D,'on');
ptSz = max(45, 130 - 7*NCH);
hPts = scatter3(ax3D, fsr_x, fsr_y, fsr_z, ptSz, zeros(NCH,1), 'filled', 'MarkerEdgeColor','k');
for i=1:NCH
    text(ax3D, fsr_x(i)*1.06, fsr_y(i)*1.06, fsr_z(i), LABELS_3D(i), ...
        'FontWeight','bold','Color','w');
end
hold(ax3D,'off');

% Enable left-click drag rotation
rot = rotate3d(fig);
rot.Enable = 'on';
% rotate3d default is left-click drag, scroll zoom; this is what you want.

%% ================= CONTROLS =================
% Mode selector
uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 0.93 0.84 0.04], ...
    'String','Input Mode', 'FontWeight','bold', 'HorizontalAlignment','left');

modePopup = uicontrol(ctrl, 'Style','popupmenu', 'Units','normalized', ...
    'Position',[0.08 0.89 0.84 0.045], ...
    'String', {'Random', 'Sliders', 'Serial (M0–M4)', 'WiFi (S1–S5 = c1–c5)'}, ...
    'Value', 1, ...
    'Callback', @onModeChanged);

uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 0.845 0.84 0.03], ...
    'String','COM port (Serial mode)', 'HorizontalAlignment','left');

[portListCell, portPick] = serialPortListForUi();
comPortPopup = uicontrol(ctrl, 'Style','popupmenu', 'Units','normalized', ...
    'Position',[0.08 0.798 0.52 0.038], ...
    'String', portListCell, ...
    'Value', min(portPick, numel(portListCell)), ...
    'Tooltip', 'Refresh after plugging USB. Pick the same COM as Arduino IDE. Close Serial Monitor first. COM1–COM20 appears if MATLAB lists no ports.');

uicontrol(ctrl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[0.62 0.798 0.30 0.038], ...
    'String', 'Refresh ports', ...
    'Callback', @onRefreshSerialPorts);

% Smoothing slider (optional, nice)
uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 0.76 0.84 0.035], ...
    'String','Smoothing (EMA α)', 'HorizontalAlignment','left');

alphaSlider = uicontrol(ctrl, 'Style','slider', 'Units','normalized', ...
    'Position',[0.08 0.73 0.84 0.03], ...
    'Min', 0.01, 'Max', 1.0, 'Value', ALPHA, ...
    'Callback', @onAlphaChanged);

alphaReadout = uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 0.695 0.84 0.03], ...
    'String', sprintf('α = %.2f', ALPHA), ...
    'HorizontalAlignment','left');

% Sliders for each channel (stack below alpha block; row pitch avoids overlap)
sliderHandles = gobjects(NCH,1);
valueTexts    = gobjects(NCH,1);
labelH = 0.032;
sldrH  = 0.026;
gapLabSldr = 0.006;
rowPitch = labelH + gapLabSldr + sldrH + 0.008; % vertical advance per FSR row
% Alpha readout ends ~0.725; start FSR labels below that with margin
yLabel1 = 0.56;
tipBottom = 0.05;
tipH = 0.055;
% If too many channels, compress row pitch slightly but keep >= rowPitch min
minPitch = labelH + gapLabSldr + sldrH + 0.004;
avail = yLabel1 - (tipBottom + tipH + 0.02); % space above tip
if (NCH-1) * rowPitch > avail
    rowPitch = max(minPitch, avail / max(NCH, 1));
end

for i = 1:NCH
    y = yLabel1 - (i-1)*rowPitch;
    ySl = y - gapLabSldr - sldrH;

    uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
        'Position',[0.08 y 0.45 labelH], ...
        'String', LABELS(i), 'HorizontalAlignment','left');

    sliderHandles(i) = uicontrol(ctrl, 'Style','slider', 'Units','normalized', ...
        'Position',[0.08 ySl 0.84 sldrH], ...
        'Min', YMIN, 'Max', YMAX, 'Value', sliderVals(i), ...
        'Callback', @(src,evt)onSliderChanged(i, src));

    valueTexts(i) = uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
        'Position',[0.55 y 0.37 labelH], ...
        'String', sprintf('%d', round(sliderVals(i))), ...
        'HorizontalAlignment','right');
end

uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 tipBottom 0.84 tipH], ...
    'String', "Tip: Drag the 3D plot with LEFT mouse to rotate.", ...
    'HorizontalAlignment','left');

%% ================= TIMER LOOP (NON-BLOCKING GUI) =================
tmr = timer( ...
    'ExecutionMode','fixedRate', ...
    'Period', DT, ...
    'TimerFcn', @tick);

% Make sure timer stops when figure closes
fig.CloseRequestFcn = @onClose;

histWallTic = tic; % same origin as t_hist_cols (wall time for history axis)
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
        if mode == 3
            xticklabels(axBar, LABELS_SERIAL);
            legend(axHist, LABELS_SERIAL, 'Location','northwest');
        elseif mode == 4
            xticklabels(axBar, LABELS_WIFI);
            legend(axHist, LABELS_WIFI, 'Location','northwest');
        else
            xticklabels(axBar, LABELS);
            legend(axHist, LABELS, 'Location','northwest');
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
        try
            if ~isvalid(fig) || ~isvalid(b) || ~isvalid(hSurf)
                return;
            end

            % ---- Generate inputs ----
            if mode == 1
                raw = makeRandomSignals(t_sim);
            elseif mode == 2
                raw = sliderVals; % 0..YMAX
            elseif mode == 3
                raw = readMux1Ch0to4(); % Serial: Arduino 2-mux line protocol
            else
                raw = readWifiC1toCN(); % WiFi JSON c1–cN -> S1–SN
            end

            % ---- EMA smoothing (bars/history only; heatmap follows raw for instant release) ----
            for k = 1:NCH
                ema(k) = ema(k) + ALPHA * (raw(k) - ema(k));
            end
            v = ema;

            % ---- Update rolling buffer + wall times (WINDOW_SEC-wide window, fixed x-axis) ----
            buf(:,1:end-1) = buf(:,2:end);
            buf(:,end) = v;
            t_now = toc(histWallTic);
            t_hist_cols(1:end-1) = t_hist_cols(2:end);
            t_hist_cols(end) = t_now;
            valid = ~isnan(t_hist_cols);
            x_rel = t_hist_cols(valid) - t_now; % seconds before “now” (matches real GUI rate)

            % ---- Update bars + history ----
            b.YData = buf(:,end)';  % bar wants row vector

            for k = 1:NCH
                hLine(k).XData = x_rel;
                hLine(k).YData = buf(k, valid);
            end

            % ---- Heat field: use raw ADC (not EMA); linear 0..100 (avoid 1000*gain saturation) ----
            intensityHeat = 100 * (raw - YMIN) / max(eps, (YMAX - YMIN));
            intensityHeat = max(0, min(100, intensityHeat));

            heat = zeros(size(Z));
            for k = 1:NCH
                dx = X - fsr_x(k);
                dy_ = Y - fsr_y(k);
                dz = Z - fsr_z(k);
                d = sqrt(dx.^2 + dy_.^2 + dz.^2);
                heat = heat + intensityHeat(k) .* exp(-(d.^2) / (2*sigma^2));
            end
            heat = min(100, heat);

            hSurf.CData = heat;
            hPts.CData  = intensityHeat; % match instantaneous heat (same as surface drive)
            set(ax3D, 'CLim', [0 100]); % match displayed intensity 0–100

            t_sim = t_sim + DT;
            drawnow limitrate;
        catch
            % Keep GUI alive even if one timer tick fails.
        end
    end

    function raw = makeRandomSignals(t)
        % Smooth-ish values 0..YMAX — strong per-channel offsets, gains, and frequencies
        ch = (1:NCH).';
        meanOff = 18 * sin(0.85 * ch + 0.9);
        amp1 = 22 + 18 * cos(0.52 * ch + 0.3);
        amp2 = 10 + 10 * sin(0.41 * ch);
        amp3 = 6 + 5 * cos(0.73 * ch);
        f1 = 0.075 + 0.055 * (ch - 1) / max(NCH - 1, 1);
        f2 = 0.048 + 0.028 * sin(0.6 * ch);
        f3 = 0.112 + 0.02 * cos(0.45 * (ch - 2));
        ph1 = ch .* (1.05 + 0.11 * ch);
        ph2 = ch .* 0.67 + 2.4;
        ph3 = ch .* 1.31 + 0.35;
        raw = 50 + meanOff ...
            + amp1 .* sin(2*pi*f1*t + ph1) ...
            + amp2 .* sin(2*pi*f2*t + ph2) ...
            + amp3 .* sin(2*pi*f3*t + ph3) ...
            + 14 * sin(2*pi*0.029*t + 0.52 * ch);
        raw = raw + randn(NCH,1) .* (2.2 + 1.8 * abs(cos(0.55 * ch)));
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

    function raw = readMux1Ch0to4()
        % Arduino loop: sprintf(padded,"%%6d", analogRead(A0)) for i=0..15 -> 96-char line + LF.
        % GUI uses mux fields 1..NCH (indices 0..NCH-1 on wire = M0–M(N-1)).
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
                raw = zeros(NCH, 1);
                % Map 0..ADC_IN_MAX_SERIAL -> 0..YMAX. If SERIAL_INVERT_ADC, use (ADC_IN_MAX_SERIAL - adc)
                % so lower sensor readings (more pressure) become higher display values.
                if SERIAL_INVERT_ADC
                    level = ADC_IN_MAX_SERIAL - mux1;
                else
                    level = mux1;
                end
                raw(:) = level * (YMAX / ADC_IN_MAX_SERIAL);
                raw = max(YMIN, min(YMAX, raw));
                lastSerialRaw = raw;
            end

            if numel(serialLineAccum) > 8000
                serialLineAccum = serialLineAccum(end-3999:end);
            end
        catch
        end



    end

    function raw = readWifiC1toCN()
        % Poll ESP32 JSON /c1-cN: mux c1..cN -> GUI S1..SN. WIFI_INVERT_ADC=false => higher ADC -> higher bar.
        raw = lastWifiRaw;
        if toc(lastWifiPollTic) < (1 / WIFI_POLL_HZ)
            return;
        end
        lastWifiPollTic = tic;
        reqFields = arrayfun(@(k) sprintf('c%d', k), 1:NCH, 'UniformOutput', false);
        try
            gotFrame = false;
            order = [activeWifiUrlIdx, setdiff(1:numel(WIFI_URLS), activeWifiUrlIdx)];
            for u = order
                try
                    resp = webread(char(WIFI_URLS(u)), wifiWebOpts);
                catch
                    continue;
                end
                adc = [];
                if isstruct(resp)
                    if all(isfield(resp, reqFields))
                        adc = zeros(NCH, 1);
                        for ii = 1:NCH
                            adc(ii) = double(resp.(reqFields{ii}));
                        end
                    end
                elseif ischar(resp) || isstring(resp)
                    wifiJson = jsondecode(char(resp));
                    if all(isfield(wifiJson, reqFields))
                        adc = zeros(NCH, 1);
                        for ii = 1:NCH
                            adc(ii) = double(wifiJson.(reqFields{ii}));
                        end
                    end
                end
                if ~isempty(adc)
                    activeWifiUrlIdx = u;
                    gotFrame = true;
                    break;
                end
            end
            if ~gotFrame
                return;
            end

            if WIFI_INVERT_ADC
                level = ADC_IN_MAX_WIFI - adc;
            else
                level = adc;
            end
            raw = level * (YMAX / ADC_IN_MAX_WIFI) * WIFI_DISPLAY_GAIN;
            raw = max(YMIN, min(YMAX, raw));
            lastWifiRaw = raw;
        catch
            % Keep last good frame on transient WiFi failures.
        end
    end
end

function r = limbRvec(zv, H, shapeK, Rmax, R_cyl, h_cone)
% Radius r(z) for surface of revolution: paraboloid z in [0,H], smooth cone to R_cyl, then cylinder.
r = zeros(size(zv));
m1 = zv <= H;
r(m1) = sqrt(max(zv(m1), 1e-8) / shapeK);
m2 = zv > H & zv <= H + h_cone;
t = (zv(m2) - H) / h_cone;
s = t.^2 .* (3 - 2*t); % smoothstep (rounded blend)
r(m2) = Rmax .* (1-s) + R_cyl .* s;
m3 = zv > H + h_cone;
r(m3) = R_cyl;
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