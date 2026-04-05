function state = updateVehicles(state, env, cfg)
% updateVehicles  Generate new background vehicles (Poisson) and advance
%                 existing ones around the shuttle loop.  Removes vehicles
%                 that have completed a full loop.

%% Generate new background vehicles
lam = cfg.veh_rate * cfg.dt;
n_new = poissrnd(lam);
for k = 1:n_new
    spd = normrnd(cfg.veh_speed_mean, cfg.veh_speed_std) * state.weather;
    spd = max(1.0, min(8.0, spd));

    lp  = rand * env.loop_length;     % Random starting position on loop
    seg = find(env.cum_dist <= lp, 1, 'last');
    seg = min(max(seg,1), env.n_seg);
    t_sg = (lp - env.cum_dist(seg)) / max(1e-6, env.seg_dist(seg));
    n1  = env.node_seq(seg);
    n2  = env.node_seq(mod(seg, env.n_seg)+1);
    xy  = env.pos(n1,:) + t_sg * (env.pos(n2,:) - env.pos(n1,:));

    v.id       = state.next_veh;
    v.loop_pos = lp;
    v.speed    = spd;
    v.x        = xy(1);
    v.y        = xy(2);
    v.dist_run = 0;

    state.vehs(end+1) = v;
    state.next_veh    = state.next_veh + 1;
end

%% Advance existing vehicles
keep = true(1, numel(state.vehs));
for k = 1:numel(state.vehs)
    state.vehs(k).loop_pos = state.vehs(k).loop_pos + state.vehs(k).speed * cfg.dt;
    state.vehs(k).dist_run = state.vehs(k).dist_run + state.vehs(k).speed * cfg.dt;

    % Update XY
    lp  = mod(state.vehs(k).loop_pos, env.loop_length);
    seg = find(env.cum_dist <= lp, 1, 'last');
    seg = min(max(seg,1), env.n_seg);
    t_sg = (lp - env.cum_dist(seg)) / max(1e-6, env.seg_dist(seg));
    n1  = env.node_seq(seg);
    n2  = env.node_seq(mod(seg, env.n_seg)+1);
    xy  = env.pos(n1,:) + t_sg * (env.pos(n2,:) - env.pos(n1,:));
    state.vehs(k).x = xy(1);
    state.vehs(k).y = xy(2);

    % Remove after one full loop (prevents unbounded growth)
    if state.vehs(k).dist_run >= env.loop_length
        keep(k) = false;
    end
end
state.vehs = state.vehs(keep);
end
