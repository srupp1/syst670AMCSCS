function [encounters, chk] = detectConflicts(state, env, cfg, t)
% detectConflicts  Compute TTC, PET, and separation for all shuttle-ped
%                  and shuttle-vehicle encounters.
%
% Encounter record fields (SIM-IIF-001):
%   t, shuttle_id, enc_type ('ped'/'veh'), agent_id, TTC, PET, min_sep, severity
%
% Optional second output chk:
%   chk.n_ped_checked  — total shuttle-ped pairs evaluated (sep <= detect_radius)
%   chk.n_veh_checked  — total shuttle-veh pairs evaluated (sep <= detect_radius)

encounters = struct('t',{},'shuttle_id',{},'enc_type',{},'agent_id',{},...
                    'TTC',{},'PET',{},'min_sep',{},'severity',{});

chk.n_ped_checked = 0;
chk.n_veh_checked = 0;

for i = 1:cfg.n_shuttles
    s = state.shuttles(i);
    if s.dwell > 0; continue; end   % Shuttle stationary at stop

    spd_s = s.speed;

    % Shuttle heading: unit vector along current loop segment
    seg_n1  = env.node_seq(s.seg);
    seg_n2  = env.node_seq(mod(s.seg, env.n_seg) + 1);
    seg_vec = env.pos(seg_n2,:) - env.pos(seg_n1,:);
    seg_len = norm(seg_vec);
    if seg_len > 1e-6
        sx = seg_vec(1) / seg_len;  sy = seg_vec(2) / seg_len;
    else
        sx = 1;  sy = 0;
    end

    %% Shuttle–Pedestrian conflicts
    for k = 1:numel(state.peds)
        p   = state.peds(k);
        dx  = p.x - s.x;
        dy  = p.y - s.y;
        sep = sqrt(dx^2 + dy^2);

        if sep > cfg.ped_detect_radius; continue; end
        chk.n_ped_checked = chk.n_ped_checked + 1;

        if sep < 1e-3; sep = 1e-3; end
        ux = dx / sep;  uy = dy / sep;

        % Closing speed = component of shuttle velocity toward the pedestrian.
        % Peds crossing perpendicular to the path yield closing ≈ 0 and are
        % skipped; only peds genuinely in the shuttle's lane register as closing.
        closing = spd_s * (sx*ux + sy*uy);

        % TTC: time until separation = min_sep
        safe_sep = cfg.min_sep_ped;
        approach_dist = sep - safe_sep;
        if approach_dist <= 0
            TTC = 0;
        elseif closing > 0.1
            TTC = approach_dist / closing;
        else
            continue   % Not closing
        end

        % PET: assume ped clears crossing in timer/2 s on average
        PET = max(0, p.timer/2 - TTC);

        % Effective TTC for severity classification:
        % Add AV advance-response buffer (cfg.ttc_buffer) to reflect that
        % the shuttle has already detected and begun responding to this
        % pedestrian from further away (e.g. 30–50 m with lidar), giving
        % an effective safety margin beyond the raw geometric TTC.
        TTC_eff = TTC + cfg.ttc_buffer;

        % Severity based on effective TTC
        if TTC_eff < cfg.ttc_high
            sev = 'high';
        elseif TTC_eff < cfg.ttc_med
            sev = 'medium';
        else
            sev = 'low';
        end

        % Log all encounters within detect radius

        enc.t          = t;
        enc.shuttle_id = i;
        enc.enc_type   = 'ped';
        enc.agent_id   = p.id;
        enc.TTC        = TTC;
        enc.PET        = PET;
        enc.min_sep    = sep;
        enc.severity   = sev;
        encounters(end+1) = enc; %#ok<AGROW>
    end

    %% Shuttle–Vehicle conflicts
    for k = 1:numel(state.vehs)
        v   = state.vehs(k);
        dx  = v.x - s.x;
        dy  = v.y - s.y;
        sep = sqrt(dx^2 + dy^2);

        if sep > cfg.veh_detect_radius; continue; end
        chk.n_veh_checked = chk.n_veh_checked + 1;
        if sep < 1e-3; sep = 1e-3; end

        % Closing speed = relative speed along loop
        rel_spd = abs(spd_s - v.speed);
        safe_sep = cfg.min_sep_veh;
        approach_dist = sep - safe_sep;

        if approach_dist <= 0
            TTC = 0;
        elseif rel_spd > 0.1
            TTC = approach_dist / rel_spd;
        else
            continue
        end

        PET = 0;    % Vehicles: PET not applicable; set 0

        % Apply AV advance-response buffer (same rationale as pedestrians)
        TTC_eff = TTC + cfg.ttc_buffer;

        if TTC_eff < cfg.ttc_high
            sev = 'high';
        elseif TTC_eff < cfg.ttc_med
            sev = 'medium';
        else
            sev = 'low';
        end

        % Log all vehicle encounters within detect radius

        enc.t          = t;
        enc.shuttle_id = i;
        enc.enc_type   = 'veh';
        enc.agent_id   = v.id;
        enc.TTC        = TTC;
        enc.PET        = PET;
        enc.min_sep    = sep;
        enc.severity   = sev;
        encounters(end+1) = enc; %#ok<AGROW>
    end
end
end
