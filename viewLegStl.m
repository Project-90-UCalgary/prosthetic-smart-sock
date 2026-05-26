function viewLegStl(stlPath, sensorSeed, showSensors)
%VIEWLEGSTL  Quick 3D preview of the prosthetic leg STL (no telemetry GUI).
%   viewLegStl()
%   viewLegStl('models/leg.stl', 42, true)

if nargin < 1 || isempty(stlPath)
    stlPath = '';
end
if nargin < 2 || isempty(sensorSeed)
    sensorSeed = 42;
end
if nargin < 3 || isempty(showSensors)
    showSensors = true;
end

[V, F, patchFaces, kneeFaces, sx, sy, sz, meta] = loadProstheticStlMesh(stlPath, 16, sensorSeed);
limbBeige = [0.86 0.80 0.68];

fig = figure('Color', 'w', 'Name', 'Prosthetic leg STL preview');
ax = axes(fig, 'Color', [1 1 1]);
hold(ax, 'on');
trisurf(F, V(:, 1), V(:, 2), V(:, 3), 'FaceColor', limbBeige, 'EdgeColor', 'none', 'Parent', ax);
if ~isempty(patchFaces)
    patch('Faces', patchFaces, 'Vertices', V, 'FaceColor', [0.55 0.72 0.90], ...
        'FaceAlpha', 0.18, 'EdgeColor', 'none', 'Parent', ax);
end
if showSensors
    scatter3(ax, sx, sy, sz, 56, 'k', 'filled', 'MarkerEdgeColor', 'w');
end
hold(ax, 'off');
axis(ax, 'equal');
view(ax, 135, 22);
xlabel(ax, 'X (mm)'); ylabel(ax, 'Y (mm)'); zlabel(ax, 'Z (mm)');
title(ax, sprintf('STL preview (seed %d) — amputation at Z=%.0f', meta.sensorSeed, meta.distalEnd(3)));
camlight(ax); lighting(ax, 'gouraud');
rotate3d on;
fprintf('Knee Z=%.1f, distal Z=%.1f, %d sensors on stump patch.\n', ...
    meta.kneePoint(3), meta.distalEnd(3), meta.nSensors);
end
