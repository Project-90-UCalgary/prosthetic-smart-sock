function [X, Y, Z, patchMask, s_x, s_y, s_z, meta] = buildProstheticLimbMesh(nSensors, sensorSeed)
%BUILDPROSTHETICLIMBMESH  Bent residual limb: thigh, knee, tapering calf.
%   [X,Y,Z,patchMask,s_x,s_y,s_z,meta] = buildProstheticLimbMesh(nSensors, sensorSeed)
%
%   Models a seated/bent leg (thigh horizontal, knee arc, calf vertical down).
%   Sixteen sensor sites are placed at random on the calf "sock patch" (anterior
%   wrap from just below the knee to the distal end), matching the CAD highlight.
%
%   patchMask — same size as X; true on faces in the sensor patch (for blue tint).
%   sensorSeed — RNG seed for reproducible random sites (default 42).

if nargin < 1 || isempty(nSensors)
    nSensors = 16;
end
if nargin < 2 || isempty(sensorSeed)
    sensorSeed = 42;
end

%% Centerline control points (thigh -> knee -> calf)
% X: thigh extends +X; calf extends -Z (vertical down).
cp = [
    1.08,  0.00,  0.00;   % thigh distal
    0.62,  0.00,  0.00;
    0.22,  0.00,  0.00;   % approach knee
    0.04,  0.00, -0.06;   % knee cap region
   -0.02,  0.00, -0.28;   % posterior knee bend
    0.00,  0.00, -0.58;   % upper calf (patch start ~here)
    0.00,  0.00, -1.12;
    0.00,  0.00, -1.68;
    0.00,  0.00, -2.12;   % calf tip (residual limb end)
];
rCp = [0.145, 0.142, 0.135, 0.128, 0.118, 0.108, 0.092, 0.062, 0.028];

Ns = 90;
Ntheta = 72;
sUniform = linspace(0, 1, Ns);

% Smooth centerline + radius along arc length
tFine = linspace(0, 1, 400);
xyzFine = interp1(linspace(0, 1, size(cp, 1)), cp, tFine, 'pchip');
rFine = interp1(linspace(0, 1, numel(rCp)), rCp, tFine, 'pchip');
ds = sqrt(sum(diff(xyzFine, 1, 1).^2, 2));
sFine = [0; cumsum(ds)];
sFine = sFine / sFine(end);

xyz = zeros(Ns, 3);
rMid = zeros(Ns, 1);
for i = 1:Ns
    idx = find(sFine >= sUniform(i) * sFine(end), 1, 'first');
    if isempty(idx)
        idx = numel(sFine);
    end
    xyz(i, :) = xyzFine(idx, :);
    rMid(i) = rFine(idx);
end

% Parallel-transport frames along centerline
T = zeros(Ns, 3);
N = zeros(Ns, 3);
B = zeros(Ns, 3);
T(1, :) = xyz(2, :) - xyz(1, :);
T(1, :) = T(1, :) / max(norm(T(1, :)), eps);
refUp = [0, 1, 0];
N(1, :) = cross(T(1, :), refUp);
if norm(N(1, :)) < 1e-6
    refUp = [0, 0, 1];
    N(1, :) = cross(T(1, :), refUp);
end
N(1, :) = N(1, :) / max(norm(N(1, :)), eps);
B(1, :) = cross(T(1, :), N(1, :));
B(1, :) = B(1, :) / max(norm(B(1, :)), eps);

for i = 2:Ns
    ti = xyz(i, :) - xyz(i - 1, :);
    ti = ti / max(norm(ti), eps);
    bi = B(i - 1, :);
    ni = cross(bi, ti);
    ni = ni / max(norm(ni), eps);
    bi = cross(ti, ni);
    bi = bi / max(norm(bi), eps);
    T(i, :) = ti;
    N(i, :) = ni;
    B(i, :) = bi;
end

% Force anterior (+X) to face the sensor patch on the calf for intuitive placement
calfStartIdx = 6; % index on centerline where calf / patch begins
for i = calfStartIdx:Ns
  desired = [1, 0, 0];
  if dot(N(i, :), desired) < 0
    N(i, :) = -N(i, :);
    B(i, :) = cross(T(i, :), N(i, :));
  end
end

thetaAxis = linspace(0, 2 * pi, Ntheta);
X = zeros(Ns, Ntheta);
Y = zeros(Ns, Ntheta);
Z = zeros(Ns, Ntheta);
patchMask = false(Ns - 1, Ntheta - 1);

% Patch spans calf section: anterior wrap (theta about +X / N direction)
uPatchMin = 0.04;
uPatchMax = 1.00;
thPatchMin = -pi * 0.55;
thPatchMax = pi * 0.55;
sPatchLo = sUniform(calfStartIdx);
sPatchHi = 1.0;

for i = 1:Ns
    p = xyz(i, :);
    ri = rMid(i);
    for j = 1:Ntheta
        th = thetaAxis(j);
        offset = ri * (cos(th) * N(i, :) + sin(th) * B(i, :));
        q = p + offset;
        X(i, j) = q(1);
        Y(i, j) = q(2);
        Z(i, j) = q(3);
    end
end

for i = 1:(Ns - 1)
    su = mean([sUniform(i), sUniform(i + 1)]);
    for j = 1:(Ntheta - 1)
        th = mean([thetaAxis(j), thetaAxis(j + 1)]);
        if su >= sPatchLo && su <= sPatchHi
            thWrap = atan2(sin(th), cos(th));
            if thWrap >= thPatchMin && thWrap <= thPatchMax
                patchMask(i, j) = true;
            end
        end
    end
end

%% Random sensor sites on calf patch
rng(sensorSeed);
s_x = zeros(nSensors, 1);
s_y = zeros(nSensors, 1);
s_z = zeros(nSensors, 1);

for k = 1:nSensors
    u = uPatchMin + (uPatchMax - uPatchMin) * rand();
    th = thPatchMin + (thPatchMax - thPatchMin) * rand();
    sTarget = sPatchLo + u * (sPatchHi - sPatchLo);
    [s_x(k), s_y(k), s_z(k)] = limbSurfacePoint(sTarget, th, sUniform, xyz, rMid, N, B);
end

meta = struct( ...
    'nSensors', nSensors, ...
    'sensorSeed', sensorSeed, ...
    'sPatchLo', sPatchLo, ...
    'sPatchHi', sPatchHi, ...
    'uPatchMin', uPatchMin, ...
    'uPatchMax', uPatchMax, ...
    'thPatchMin', thPatchMin, ...
    'thPatchMax', thPatchMax, ...
    'calfStartIdx', calfStartIdx);
end

function [x, y, z] = limbSurfacePoint(sTarget, theta, sUniform, xyz, rMid, N, B)
idx = find(sUniform >= sTarget, 1, 'first');
if isempty(idx)
    idx = numel(sUniform);
end
if idx > 1 && sUniform(idx) > sTarget
    idxLo = idx - 1;
    idxHi = idx;
    t = (sTarget - sUniform(idxLo)) / max(sUniform(idxHi) - sUniform(idxLo), eps);
    p = (1 - t) * xyz(idxLo, :) + t * xyz(idxHi, :);
    r = (1 - t) * rMid(idxLo) + t * rMid(idxHi);
    n = (1 - t) * N(idxLo, :) + t * N(idxHi, :);
    b = (1 - t) * B(idxLo, :) + t * B(idxHi, :);
else
    p = xyz(idx, :);
    r = rMid(idx);
    n = N(idx, :);
    b = B(idx, :);
end
n = n / max(norm(n), eps);
b = b / max(norm(b), eps);
q = p + r * (cos(theta) * n + sin(theta) * b);
x = q(1);
y = q(2);
z = q(3);
end
