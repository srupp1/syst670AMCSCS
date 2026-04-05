function state = updatePedestrians(state, env, cfg)
% updatePedestrians  Generate new pedestrian arrivals (Poisson) and advance
%                    existing pedestrians.  Removes pedestrians that have
%                    finished crossing.

%% Generate new arrivals at each crossing node
for c = 1:numel(env.crossing_nodes)
    nd = env.crossing_nodes(c);

    % Poisson: expected arrivals = rate * dt
    deg_factor = min(3, degree(env.G, nd));
    lam = cfg.ped_rate_base * deg_factor * cfg.dt;
    n_arrivals = poissrnd(lam);

    for k = 1:n_arrivals
        % Random perpendicular offset from node (models crossing direction)
        angle  = rand * 2 * pi;
        offset = 1.5 + rand * 2;           % 1.5–3.5 m from node centre
        spd    = normrnd(cfg.ped_speed_mean, cfg.ped_speed_std);
        spd    = max(0.5, spd);

        p.id    = state.next_ped;
        p.x     = env.pos(nd,1) + offset * cos(angle);
        p.y     = env.pos(nd,2) + offset * sin(angle);
        p.vx    = spd * cos(angle + pi/2);  % Walking perpendicular to offset
        p.vy    = spd * sin(angle + pi/2);
        p.timer = cfg.ped_cross_time + rand * 4;   % Cross time with jitter [s]
        p.node  = nd;

        state.peds(end+1) = p;
        state.next_ped    = state.next_ped + 1;
    end
end

%% Advance existing pedestrians
keep = true(1, numel(state.peds));
for k = 1:numel(state.peds)
    state.peds(k).x     = state.peds(k).x + state.peds(k).vx * cfg.dt;
    state.peds(k).y     = state.peds(k).y + state.peds(k).vy * cfg.dt;
    state.peds(k).timer = state.peds(k).timer - cfg.dt;
    if state.peds(k).timer <= 0
        keep(k) = false;
    end
end
state.peds = state.peds(keep);
end
