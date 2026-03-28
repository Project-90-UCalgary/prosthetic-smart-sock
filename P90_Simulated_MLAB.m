function prosthetic_paraboloid_gui
% prosthetic_paraboloid_gui.m
% 6-channel prosthetic visualization:
% - Limb surface: paraboloid cup + smooth cone + vertical cylinder
% - Live bars + rolling history
% - 3D heatmap with 6 sensor points
% - GUI sliders + mode toggle (Random / Sliders / Serial)
% - Serial: pairs with 4_16_mux_full_test_1_2_.ino — mux1 (A0) ch 0–4
% - Rotate limb with left-click dragging (rotate3d)

clearvars; close all; clc;

%% ================= SETTINGS =================
NCH = 6;
LABELS = ["FSR1","FSR2","POT1","POT2","POT3","POT4"];
LABELS_SERIAL = ["M0","M1","M2","M3","M4","—"];
LABELS_3D = ["M0","M1","M2","M3","M4","—"]; % 3D map: mux ch 0–4 + unused sixth site

SAMPLE_HZ  = 50;
DT         = 1 / SAMPLE_HZ;
WINDOW_SEC = 10;
maxlen     = round(SAMPLE_HZ * WINDOW_SEC);

YMIN = 0;
YMAX = 50;             % display 0..50; serial: raw = adc * (50/1023)
ADC_IN_MAX = 1023;     % Arduino analogRead full scale

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
x_hist = linspace(-WINDOW_SEC, 0, maxlen);

% Mode: 1=Random, 2=Sliders, 3=Serial (Arduino 2-mux sketch)
mode = 1;

% Slider values storage (0..YMAX)
sliderVals = 25 * ones(NCH,1);

% Serial (Arduino streams 16 pairs × 12 chars: "%6d%6d" = A0 then A1 per mux index)
serialHandle = [];           % serialport object, empty when closed
lastSerialRaw = zeros(NCH,1); % hold last good frame if a read fails
serialLineAccum = char([]);  % bytes until LF (avoids readline timeout warnings)
BYTES_PER_PAIR = 12;
N_MUX_CH = 16;

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

% Five mux sites on the limb + one unused marker (cylinder, top)
s_th = zeros(NCH, 1);
s_th(1:5) = (0:4).' * (2*pi/5) + 0.18; % spread around circumference
s_th(6) = 0;
z_s = zeros(NCH, 1);
z_s(1) = 0.28 * H;                          % paraboloid, lower
z_s(2) = 0.52 * H;                          % paraboloid, mid
z_s(3) = 0.82 * H;                          % paraboloid, near rim
z_s(4) = H + 0.22 * H_cyl;                  % vertical stem (flush with rim)
z_s(5) = H + 0.50 * H_cyl;                  % stem mid
z_s(6) = H + 0.88 * H_cyl;                  % stem upper (unused ch)
r_s = limbRvec(z_s, H, shapeK, Rmax, R_cyl, h_cone);
s_x = r_s .* cos(s_th);
s_y = r_s .* sin(s_th);
s_z = z_s;

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
ylabel(axBar, 'Level (0–50)');
title(axBar, 'Live Values');
grid(axBar, 'on');

% ---- History ----
axHist = nexttile(t, 3);
hold(axHist,'on');
hLine = gobjects(NCH,1);
for i=1:NCH
    hLine(i) = plot(axHist, x_hist, buf(i,:), 'LineWidth', 1.2);
end
hold(axHist,'off');
xlim(axHist, [-WINDOW_SEC 0]);
ylim(axHist, [YMIN YMAX]);
xlabel(axHist, 'Time (s) [0 = now]');
ylabel(axHist, 'Level (0–50)');
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
colormap(ax3D, hot);
cb = colorbar(ax3D);
cb.Label.String = 'Intensity (0..100)';

hold(ax3D,'on');
hPts = scatter3(ax3D, s_x, s_y, s_z, 110, zeros(NCH,1), 'filled', 'MarkerEdgeColor','k');
for i=1:NCH
    text(ax3D, s_x(i)*1.06, s_y(i)*1.06, s_z(i), LABELS_3D(i), ...
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
    'String', {'Random', 'Sliders', 'Serial (Mux1 ch0–4)'}, ...
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

% Sliders for each channel
sliderHandles = gobjects(NCH,1);
valueTexts    = gobjects(NCH,1);

y0 = 0.64;
dy = 0.105;

for i = 1:NCH
    y = y0 - (i-1)*dy;

    uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
        'Position',[0.08 y 0.45 0.035], ...
        'String', LABELS(i), 'HorizontalAlignment','left');

    sliderHandles(i) = uicontrol(ctrl, 'Style','slider', 'Units','normalized', ...
        'Position',[0.08 y-0.035 0.84 0.03], ...
        'Min', YMIN, 'Max', YMAX, 'Value', sliderVals(i), ...
        'Callback', @(src,evt)onSliderChanged(i, src));

    valueTexts(i) = uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
        'Position',[0.55 y 0.37 0.035], ...
        'String', sprintf('%d', round(sliderVals(i))), ...
        'HorizontalAlignment','right');
end

uicontrol(ctrl, 'Style','text', 'Units','normalized', ...
    'Position',[0.08 0.06 0.84 0.06], ...
    'String', "Tip: Drag the 3D plot with LEFT mouse to rotate.", ...
    'HorizontalAlignment','left');

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
        mode = modePopup.Value; % 1 random, 2 sliders, 3 serial
        if mode == 3 && prev ~= 3
            openSerialPort();
        elseif mode ~= 3 && prev == 3
            closeSerialPort();
        end
        if mode == 3
            xticklabels(axBar, LABELS_SERIAL);
            legend(axHist, LABELS_SERIAL, 'Location','northwest');
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
        if ~isvalid(fig) || ~isvalid(b) || ~isvalid(hSurf)
            return;
        end

        % ---- Generate inputs ----
        if mode == 1
            raw = makeRandomSignals(t_sim);
        elseif mode == 2
            raw = sliderVals; % 0..YMAX
        else
            raw = readMux1Ch0to4(); % Serial: Arduino 2-mux line protocol
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

        % ---- Heat field: use raw ADC (not EMA); absolute scale (no per-frame min–max) ----
        intensityHeat = 1000 * (raw - YMIN) / max(eps, (YMAX - YMIN));
        intensityHeat = max(0, min(100, intensityHeat));

        heat = zeros(size(Z));
        for k = 1:NCH
            dx = X - s_x(k);
            dy_ = Y - s_y(k);
            dz = Z - s_z(k);
            d = sqrt(dx.^2 + dy_.^2 + dz.^2);
            heat = heat + intensityHeat(k) .* exp(-(d.^2) / (2*sigma^2));
        end
        heat = min(100, heat);

        hSurf.CData = heat;
        hPts.CData  = intensityHeat; % match instantaneous heat (same as surface drive)
        set(ax3D, 'CLim', [0 100]); % fixed scale so cooling shows immediately

        t_sim = t_sim + DT;
        drawnow limitrate;
    end

    function raw = makeRandomSignals(t)
        % Smooth-ish values 0..YMAX
        raw = zeros(NCH,1);

        raw(1) = 29 + 16*sin(2*pi*0.12*t) + 3*sin(2*pi*0.03*t + 0.7);
        raw(2) = 26 + 14*sin(2*pi*0.10*t + 1.2) + 2.5*sin(2*pi*0.025*t + 2.1);
        raw(3) = 25 + 20*sin(2*pi*0.25*t);
        raw(4) = 25 + 15*sin(2*pi*0.18*t + 0.7);
        raw(5) = 25 + 12*sin(2*pi*0.30*t + 2.1);
        raw(6) = 25 + 10*sin(2*pi*0.40*t + 0.5);

        raw = raw + randn(NCH,1) * 1;
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
        % Arduino 4_16_mux_full_test_1_2_.ino: per index i, sprintf("%6d%6d", A0, A1)
        % Mux1 = A0; take logical channels 0..4 -> GUI rows 1..5; row 6 unused (0).
        % Assemble lines with read(n,uint8) so partial UART chunks do not trigger readline timeouts.
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

            needLen = N_MUX_CH * BYTES_PER_PAIR;
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
                mux1 = zeros(5, 1);
                for k = 1:5
                    off = (k - 1) * BYTES_PER_PAIR;
                    seg = line(off + (1:6));
                    mux1(k) = str2double(strtrim(seg));
                end
                if any(isnan(mux1))
                    continue;
                end
                raw = zeros(NCH, 1);
                % Map Arduino 0..ADC_IN_MAX into display 0..YMAX
                raw(1:5) = mux1 * (YMAX / ADC_IN_MAX)*20;
                raw(6) = 0;
                raw = max(YMIN, min(YMAX, raw));
                lastSerialRaw = raw;
            end

            if numel(serialLineAccum) > 8000
                serialLineAccum = serialLineAccum(end-3999:end);
            end
        catch
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