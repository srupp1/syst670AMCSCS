function env = loadEnvironment(mat_file, cfg)
% loadEnvironment  Load G.mat and build campus environment struct.
%
% Returns env with fields:
%   G              - MATLAB graph object (undirected, weighted by distance)
%   pos            - [N x 2] node XY positions [m], node 1 = Library = origin
%   names          - {N x 1} node name strings
%   node_seq       - full waypoint node sequence for one shuttle loop
%   seg_dist       - [1 x M] distance of each segment in node_seq [m]
%   cum_dist       - [1 x M+1] cumulative distances (0 to loop_length)
%   loop_length    - total loop distance [m]
%   stop_nodes     - route stop node indices (excluding repeated first)
%   stop_cum_dist  - cumulative distance to each route stop along node_seq
%   baseline_leg_t - baseline travel time per leg at nominal speed [s]
%   crossing_nodes - nodes that are pedestrian crossing points

data = load(mat_file);

src  = double(data.src_idx);   % [18 x 1]
tgt  = double(data.tgt_idx);
dx   = data.dx;
dy   = data.dy;
n_edges = numel(src);

% --- Edge weights (Euclidean distance) ---
w = sqrt(dx.^2 + dy.^2);

% --- Build undirected weighted graph ---
G = graph(src, tgt, w);
n_nodes = numnodes(G);

% --- Reconstruct node XY positions via BFS from node 1 (origin) ---
pos     = zeros(n_nodes, 2);
visited = false(n_nodes, 1);
visited(1) = true;
queue   = 1;
while ~isempty(queue)
    u = queue(1);  queue = queue(2:end);
    for e = 1:n_edges
        if src(e) == u && ~visited(tgt(e))
            v = tgt(e);
            pos(v,:) = pos(u,:) + [dx(e), dy(e)];
            visited(v) = true;  queue(end+1) = v;
        elseif tgt(e) == u && ~visited(src(e))
            v = src(e);
            pos(v,:) = pos(u,:) - [dx(e), dy(e)];
            visited(v) = true;  queue(end+1) = v;
        end
    end
end

% --- Add XY and Name to graph node table ---
names = cell(n_nodes, 1);
for i = 1:n_nodes; names{i} = sprintf('Node%d', i); end
for e = 1:n_edges
    names{src(e)} = extractStr(data.src, e);
    names{tgt(e)} = extractStr(data.tgt, e);
end
G.Nodes.Name = names;
G.Nodes.X    = pos(:,1);
G.Nodes.Y    = pos(:,2);

% --- Route: stitch shortest paths between consecutive stops ---
route       = double(data.route);      % e.g. [1 2 3 4 5 6 8 7 9 1]
n_legs      = numel(route) - 1;       % circular: last == first
node_seq    = [];
for i = 1:n_legs
    sp = shortestpath(G, route(i), route(i+1));
    node_seq = [node_seq, sp(1:end-1)]; %#ok<AGROW>
end
% node_seq is a closed loop; last step wraps back to node_seq(1)

n_seg    = numel(node_seq);
seg_dist = zeros(1, n_seg);
for i = 1:n_seg
    a = node_seq(i);
    b = node_seq(mod(i, n_seg) + 1);
    seg_dist(i) = norm(pos(a,:) - pos(b,:));
end
cum_dist    = [0, cumsum(seg_dist)];
loop_length = sum(seg_dist);

% --- Find cumulative distances to each route stop ---
stop_nodes   = route(1:n_legs);    % [1 x n_legs], first n_legs stops
stop_cum_dist = zeros(1, n_legs);
search_from  = 1;
for i = 1:n_legs
    target = stop_nodes(i);
    rel = find(node_seq(search_from:end) == target, 1);
    if isempty(rel)
        rel = find(node_seq == target, 1);
        idx = rel;
    else
        idx = rel + search_from - 1;
    end
    stop_cum_dist(i) = cum_dist(idx);
    search_from = idx + 1;
    if search_from > n_seg; search_from = 1; end
end

% --- Baseline leg travel times at nominal speed ---
% Includes dwell_time so that on-time performance is measured as
% "departure-to-departure" rather than "arrival-to-arrival".
% Without this, every trip shows a false ~37% delay due to stop dwell.
leg_dists = diff([stop_cum_dist, stop_cum_dist(1) + loop_length]);
baseline_leg_t = leg_dists / cfg.speed_mean + cfg.dwell_time;

% --- Pedestrian crossing nodes (all route stops, higher-degree nodes) ---
deg = degree(G, (1:n_nodes)');
crossing_nodes = unique([stop_nodes(:); find(deg >= 3)]);

% --- Pack output ---
env.G              = G;
env.n_nodes        = n_nodes;
env.n_edges        = n_edges;
env.src_idx        = src;
env.tgt_idx        = tgt;
env.pos            = pos;
env.names          = names;
env.node_seq       = node_seq;
env.seg_dist       = seg_dist;
env.cum_dist       = cum_dist;
env.loop_length    = loop_length;
env.n_seg          = n_seg;
env.route          = route;
env.stop_nodes     = stop_nodes;
env.stop_cum_dist  = stop_cum_dist;
env.baseline_leg_t = baseline_leg_t;
env.n_legs         = n_legs;
env.crossing_nodes = crossing_nodes;

fprintf('Campus graph: %d nodes, %d edges\n', n_nodes, n_edges);
fprintf('Shuttle loop: %.0f m  (%.1f min at %.1f m/s)\n', ...
    loop_length, loop_length/cfg.speed_mean/60, cfg.speed_mean);
fprintf('Route stops: ');
for i = 1:n_legs; fprintf('%s → ', names{stop_nodes(i)}); end
fprintf('(loop)\n\n');
end

% -------------------------------------------------------------------------
function s = extractStr(cell_or_arr, idx)
% Handle MATLAB cell/char array variations from mat file loading
    raw = cell_or_arr{idx};
    if iscell(raw);  raw = raw{1}; end
    s = char(raw);
end
