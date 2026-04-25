function perception = computePerception(state, env, cfg, t)
% computePerception  Model shuttle perception of nearby agents.
%
% Perception record fields (SIM-IIF-003):
%   true_x, true_y, det_x, det_y, detected, pred_err, latency

perception = struct('t',{},'shuttle_id',{},'agent_type',{},...
                    'true_x',{},'true_y',{},'det_x',{},'det_y',{},...
                    'detected',{},'pred_err',{},'latency',{});

for i = 1:cfg.n_shuttles
    s = state.shuttles(i);

    % Combine nearby peds and vehs into one list
    agents = [];
    for k = 1:numel(state.peds)
        p = state.peds(k);
        sep = sqrt((p.x-s.x)^2 + (p.y-s.y)^2);
        if sep <= cfg.ped_detect_radius * 2
            agents(end+1).x    = p.x; %#ok<AGROW>
            agents(end).y      = p.y;
            agents(end).vx     = p.vx;
            agents(end).vy     = p.vy;
            agents(end).type   = 'ped';
        end
    end
    for k = 1:numel(state.vehs)
        v = state.vehs(k);
        sep = sqrt((v.x-s.x)^2 + (v.y-s.y)^2);
        if sep <= cfg.veh_detect_radius * 2
            lp_v = mod(v.loop_pos, env.loop_length);
            seg_v = find(env.cum_dist <= lp_v, 1, 'last');
            seg_v = min(max(seg_v, 1), env.n_seg);
            n1v = env.node_seq(seg_v);
            n2v = env.node_seq(mod(seg_v, env.n_seg) + 1);
            ddx = env.pos(n2v,1) - env.pos(n1v,1);
            ddy = env.pos(n2v,2) - env.pos(n1v,2);
            dd  = sqrt(ddx^2 + ddy^2);
            if dd > 1e-6
                vvx = v.speed * ddx / dd;
                vvy = v.speed * ddy / dd;
            else
                vvx = 0;  vvy = 0;
            end
            agents(end+1).x    = v.x; %#ok<AGROW>
            agents(end).y      = v.y;
            agents(end).vx     = vvx;
            agents(end).vy     = vvy;
            agents(end).type   = 'veh';
        end
    end

    p_det = cfg.detect_prob;

    for k = 1:numel(agents)
        a = agents(k);
        detected = rand < p_det;
        latency  = max(0, normrnd(cfg.latency_mean, cfg.latency_std));

        % Noisy measurement
        det_x = a.x + normrnd(0, cfg.pos_noise_std);
        det_y = a.y + normrnd(0, cfg.pos_noise_std);

        % Predicted position at t + pred_horizon using constant velocity
        pred_x = det_x + a.vx * cfg.pred_horizon;
        pred_y = det_y + a.vy * cfg.pred_horizon;
        true_future_x = a.x + a.vx * cfg.pred_horizon;
        true_future_y = a.y + a.vy * cfg.pred_horizon;
        pred_err = sqrt((pred_x - true_future_x)^2 + (pred_y - true_future_y)^2);

        pr.t           = t;
        pr.shuttle_id  = i;
        pr.agent_type  = a.type;
        pr.true_x      = a.x;
        pr.true_y      = a.y;
        pr.det_x       = det_x;
        pr.det_y       = det_y;
        pr.detected    = detected;
        pr.pred_err    = pred_err;
        pr.latency     = latency;
        perception(end+1) = pr; %#ok<AGROW>
    end
end
end
