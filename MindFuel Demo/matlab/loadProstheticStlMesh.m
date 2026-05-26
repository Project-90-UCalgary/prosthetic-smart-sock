function [V, F, patchFaces, kneeFaces, s_x, s_y, s_z, meta] = loadProstheticStlMesh(stlPath, nSensors, sensorSeed)
%LOADPROSTHETICSTLMESH  Load leg STL in native CAD orientation; sensors on distal stump.
%   Uses the export orientation from models/leg.stl (no re-orientation).
%   Distal amputation: high +X, low Z.  Knee: bend toward +Z / lower +X.

if nargin < 1 || strlength(string(stlPath)) == 0
    stlPath = defaultLegStlPath();
end
if nargin < 2 || isempty(nSensors)
    nSensors = 16;
end
if nargin < 3 || isempty(sensorSeed)
    sensorSeed = 42;
end

stlPath = char(stlPath);
if ~isfile(stlPath)
    error('loadProstheticStlMesh:FileNotFound', 'STL not found: %s', stlPath);
end

TR = stlread(stlPath);
V = TR.Points;
F = TR.ConnectivityList;
[V, F] = mergeDuplicateVertices(V, F, 1e-4);

% Landmarks for May Prosthetic Assembly export (native coords, mm)
distalEnd = distalTipVertex(V);
kneePoint = mean(V(V(:, 3) >= 50 & V(:, 3) <= 100 & V(:, 1) >= 115 & V(:, 1) <= 175, :), 1);
if any(isnan(kneePoint))
    error('loadProstheticStlMesh:KneeNotFound', 'Could not find knee landmark.');
end

stumpVec = kneePoint - distalEnd;
stumpLen = norm(stumpVec);
if stumpLen < 1
    error('loadProstheticStlMesh:DegenerateAxis', 'Stump axis length is zero.');
end

% Native CAD orientation (identity transform)
R = eye(3);

% t = 0 at distal (amputation), t = 1 at knee
t = projectAlongAxis(V, distalEnd, kneePoint);
perp = perpendicularDistance(V, distalEnd, kneePoint);
perpLim = prctile(perp(t > 0.05 & t < 0.95), 90);
if ~isfinite(perpLim) || perpLim < 15
    perpLim = 42;
end

% Full lower leg: distal tip (t=0) up to just below knee (exclude knee cap)
tPatchLo = 0.02;
tPatchHi = 0.82;
patchVert = (t >= tPatchLo) & (t <= tPatchHi) & (perp <= perpLim * 1.10) & (t <= 1.02);
kneeVert = (t >= 0.82) & (t <= 0.98) & (perp <= perpLim * 1.15);

patchFaces = F(sum(patchVert(F), 2) >= 2, :);
kneeFaces = F(sum(kneeVert(F), 2) >= 2, :);

if sum(patchVert) < nSensors
    error('loadProstheticStlMesh:PatchTooSmall', ...
        'Only %d stump vertices; need %d.', sum(patchVert), nSensors);
end

% Fixed, evenly spaced sites along the stump (length + around circumference)
pick = fixedSensorSites(V, patchVert, t, distalEnd, kneePoint, nSensors, tPatchLo, tPatchHi);
s_x = V(pick, 1);
s_y = V(pick, 2);
s_z = V(pick, 3);

meta = struct( ...
    'stlPath', stlPath, ...
    'nativeOrientation', true, ...
    'nVertices', size(V, 1), ...
    'nFaces', size(F, 1), ...
    'nSensors', nSensors, ...
    'sensorSeed', sensorSeed, ...
    'distalEnd', distalEnd, ...
    'kneePoint', kneePoint, ...
    'stumpLen', stumpLen, ...
    'tPatchLo', tPatchLo, ...
    'tPatchHi', tPatchHi, ...
    'perpLim', perpLim, ...
    'rotation', R);
end

function p = distalTipVertex(V)
% Amputation opening: high +X, low Z on updated assembly export.
zCut = min(V(:, 3)) + 25;
m = V(:, 3) <= zCut;
if nnz(m) < 10
    m = true(size(V, 1), 1);
end
idx = find(m);
[~, pick] = max(V(idx, 1) + 0.05 * V(idx, 3));
p = V(idx(pick), :);
end

function t = projectAlongAxis(V, p0, p1)
axisVec = p1 - p0;
L2 = max(dot(axisVec, axisVec), eps);
t = ((V - p0) * axisVec') / L2;
end

function d = perpendicularDistance(V, p0, p1)
axisVec = p1 - p0;
L = norm(axisVec);
if L < eps
    d = zeros(size(V, 1), 1);
    return;
end
u = axisVec / L;
proj = ((V - p0) * u') * u;
perpVec = (V - p0) - proj;
d = sqrt(sum(perpVec.^2, 2));
end

function pick = fixedSensorSites(V, mask, t, distalEnd, kneePoint, n, tLo, tHi)
%FIXEDSENSORSITES  Deterministic sensor layout: 16 stations tip -> below knee.
%   Even spacing along the stump axis and staggered around the circumference.

idx = find(mask);
if numel(idx) < n
    error('loadProstheticStlMesh:PatchTooSmall', 'Need %d patch verts, have %d.', n, numel(idx));
end

axisVec = kneePoint - distalEnd;
L = norm(axisVec);
u = axisVec / max(L, eps);

% Local frame: u = axis, n1/n2 = perpendicular
ref = [0, 0, 1];
if abs(dot(u, ref)) > 0.9
    ref = [0, 1, 0];
end
n1 = cross(u, ref);
n1 = n1 / max(norm(n1), eps);
n2 = cross(u, n1);

targets = linspace(tLo, tHi, n);
pick = zeros(n, 1);
used = false(size(V, 1), 1);
band = 0.028;

for k = 1:n
    tk = targets(k);
    ang = 2 * pi * (k - 1) / n;
    ringDir = cos(ang) * n1 + sin(ang) * n2;

    local = abs(t(idx) - tk) <= band & ~used(idx);
    if nnz(local) < 2
        local = abs(t(idx) - tk) <= band * 2.5 & ~used(idx);
    end
    if nnz(local) < 1
        [~, j] = min(abs(t(idx) - tk) + 1e6 * used(idx));
        pick(k) = idx(j);
        used(pick(k)) = true;
        continue;
    end

    cand = idx(local);
    P = V(cand, :) - distalEnd;
    radial = P - (P * u') * u;
    rd = sqrt(sum(radial.^2, 2));
    rd(rd < 1e-6) = 1e-6;
    radial = radial ./ rd;
    score = radial * ringDir' - 0.25 * abs(t(cand) - tk);
    [~, j] = max(score);
    pick(k) = cand(j);
    used(pick(k)) = true;
end
end

function p = defaultLegStlPath()
repoDir = fileparts(mfilename('fullpath'));
p = fullfile(repoDir, 'models', 'leg.stl');
end

function [V2, F2] = mergeDuplicateVertices(V, F, tol)
[Vu, ~, ic] = uniquetol(V, tol, 'ByRows', true, 'DataScale', 1);
F2 = ic(F);
V2 = Vu;
end
