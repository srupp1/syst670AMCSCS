function state = initReplication(env, cfg)
% initReplication  Initialize all agent states for one Monte Carlo replication.
% Called at the start of each replication after rng() is set.

% Weather factor (1=fair, <1=degraded; affects speeds and detection)
weather = max(0.5, normrnd(cfg.weather_mean, cfg.weather_std));

%% Shuttle agents
% Evenly space shuttles around the loop
shuttles = struct();
loop_offset = env.loop_length / cfg.n_shuttles;

for i = 1:cfg.n_shuttles
    lp = mod((i-1) * loop_offset, env.loop_length);

    % Find which segment this loop position falls in
    seg = find(env.cum_dist <= lp, 1, 'last');
    seg = min(seg, env.n_seg);
    t_seg = (lp - env.cum_dist(seg)) / max(1e-6, env.seg_dist(seg));

    % XY position
    n1 = env.node_seq(seg);
    n2 = env.node_seq(mod(seg, env.n_seg) + 1);
    xy = env.pos(n1,:) + t_seg * (env.pos(n2,:) - env.pos(n1,:));

    % Determine which stop is next for this shuttle
    stop_idx = find(env.stop_cum_dist >= lp, 1);
    if isempty(stop_idx); stop_idx = 1; end

    speed = normrnd(cfg.speed_mean, cfg.speed_std) * weather;
    speed = max(1.0, min(6.0, speed));

    shuttles(i).id           = i;
    shuttles(i).loop_pos     = lp;        % Cumulative dist along loop [m]
    shuttles(i).seg          = seg;       % Current segment index
    shuttles(i).seg_t        = t_seg;     % Progress in segment [0,1]
    shuttles(i).x            = xy(1);
    shuttles(i).y            = xy(2);
    shuttles(i).speed        = speed;
    shuttles(i).prev_speed   = speed;
    shuttles(i).dwell        = 0;         % Remaining dwell time [s]
    shuttles(i).stop_idx     = stop_idx;  % Next stop index
    shuttles(i).leg_start_t  = cfg.t_start; % Initialise to sim start (not 0)
    shuttles(i).prev_accel       = 0;     % Previous acceleration [m/s^2]
    shuttles(i).jerk_sq_sum      = 0;    % Sum of squared jerk [m/s^3]^2
    shuttles(i).jerk_n           = 0;    % Step count for jerk RMS
    shuttles(i).brake_jerk_sq_sum = 0;  % Sum of squared jerk during braking
    shuttles(i).brake_jerk_n     = 0;   % Braking step count
end

%% Pedestrian agents (none at start; generated dynamically)
peds = struct('id',{},'x',{},'y',{},'vx',{},'vy',{},'timer',{},'node',{});

%% Background vehicles (none at start; generated dynamically)
vehs = struct('id',{},'loop_pos',{},'speed',{},'x',{},'y',{},'dist_run',{});

state.shuttles   = shuttles;
state.peds       = peds;
state.vehs       = vehs;
state.weather    = weather;
state.next_ped   = 1;
state.next_veh   = 1;
end
