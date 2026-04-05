function [state, trips] = updateShuttles(state, env, cfg, t)
% updateShuttles  Advance shuttle positions by cfg.dt seconds.
% Returns completed trip records (struct array, may be empty).

trips = struct('shuttle_id',{},'leg',{},'start_node',{},'end_node',{},...
               'actual_t',{},'baseline_t',{},'delay_pct',{},'t',{});

for i = 1:cfg.n_shuttles
    s = state.shuttles(i);

    % --- Dwell at stop ---
    if s.dwell > 0
        s.dwell = s.dwell - cfg.dt;
        state.shuttles(i) = s;
        continue
    end

    % --- Sample speed with small variation each step ---
    new_speed = normrnd(cfg.speed_mean, cfg.speed_std) * state.weather;
    new_speed = max(1.0, min(6.0, new_speed));

    % Acceleration [m/s^2] = Δv / dt
    accel = (new_speed - s.prev_speed) / cfg.dt;

    % Jerk [m/s^3] = Δaccel / dt  (proper derivative of acceleration)
    jerk = (accel - s.prev_accel) / cfg.dt;

    s.jerk_sq_sum = s.jerk_sq_sum + jerk^2;
    s.jerk_n      = s.jerk_n + 1;

    % Braking smoothness: track jerk only during deceleration events
    if accel < 0
        s.brake_jerk_sq_sum = s.brake_jerk_sq_sum + jerk^2;
        s.brake_jerk_n      = s.brake_jerk_n + 1;
    end

    s.prev_accel = accel;
    s.prev_speed = s.speed;
    s.speed      = new_speed;

    % --- Advance along loop ---
    dist_to_travel = s.speed * cfg.dt;
    s.loop_pos = s.loop_pos + dist_to_travel;

    % --- Check if shuttle passed the next route stop ---
    next_stop_d = env.stop_cum_dist(s.stop_idx);
    % Handle wrap-around: if stop is behind current loop_pos
    if s.loop_pos >= env.loop_length
        s.loop_pos = mod(s.loop_pos, env.loop_length);
    end

    % Check if we passed the stop this step (handle wrap)
    passed = false;
    prev_lp = s.loop_pos - dist_to_travel;
    if prev_lp < 0; prev_lp = prev_lp + env.loop_length; end
    if prev_lp <= next_stop_d && s.loop_pos >= next_stop_d
        passed = true;
    elseif s.loop_pos < prev_lp  % wrapped around
        passed = true;
    end

    if passed
        % Record completed leg as a trip
        leg_i  = s.stop_idx;
        prev_i = mod(leg_i - 2, env.n_legs) + 1;
        actual_t   = t - s.leg_start_t;
        baseline_t = env.baseline_leg_t(prev_i);
        delay_pct  = 100 * (actual_t - baseline_t) / max(baseline_t, 1);

        tr.shuttle_id  = i;
        tr.leg         = leg_i;
        tr.start_node  = env.stop_nodes(prev_i);
        tr.end_node    = env.stop_nodes(leg_i);
        tr.actual_t    = actual_t;
        tr.baseline_t  = baseline_t;
        tr.delay_pct   = delay_pct;
        tr.t           = t;
        trips(end+1) = tr; %#ok<AGROW>

        % Start dwell and advance to next stop
        s.dwell       = cfg.dwell_time;
        s.leg_start_t = t;
        s.stop_idx    = mod(s.stop_idx, env.n_legs) + 1;
    end

    % --- Update segment index and XY position ---
    lp   = s.loop_pos;
    seg  = find(env.cum_dist <= lp, 1, 'last');
    seg  = min(max(seg, 1), env.n_seg);
    t_sg = (lp - env.cum_dist(seg)) / max(1e-6, env.seg_dist(seg));
    n1   = env.node_seq(seg);
    n2   = env.node_seq(mod(seg, env.n_seg) + 1);
    xy   = env.pos(n1,:) + t_sg * (env.pos(n2,:) - env.pos(n1,:));

    s.seg   = seg;
    s.seg_t = t_sg;
    s.x     = xy(1);
    s.y     = xy(2);

    state.shuttles(i) = s;
end
end
