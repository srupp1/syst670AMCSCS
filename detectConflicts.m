function encounters = detectConflicts(state, cfg, t)
% detectConflicts  Compute TTC, PET, and separation for all shuttle-ped
%                  and shuttle-vehicle encounters.
%
% Encounter record fields (SIM-IIF-001):
%   t, shuttle_id, enc_type ('ped'/'veh'), TTC, PET, min_sep, severity

encounters = struct('t',{},'shuttle_id',{},'enc_type',{},...
                    'TTC',{},'PET',{},'min_sep',{},'severity',{});

for i = 1:cfg.n_shuttles
    s = state.shuttles(i);
    if s.dwell > 0; continue; end   % Shuttle stationary at stop

    sv = [s.speed * cos(atan2(0,1)), s.speed * sin(atan2(0,1))];
    % Use heading from segment direction
    nd = state.shuttles(i);
    % Direction from seg_t: approximate heading from current position
    % (sufficient for magnitude-based TTC)
    spd_s = s.speed;

    %% Shuttle–Pedestrian conflicts
    for k = 1:numel(state.peds)
        p   = state.peds(k);
        dx  = p.x - s.x;
        dy  = p.y - s.y;
        sep = sqrt(dx^2 + dy^2);

        if sep > cfg.ped_detect_radius; continue; end

        % Relative velocity (shuttle approaching ped at speed spd_s)
        % Closing speed ≈ shuttle speed projected toward pedestrian
        if sep < 1e-3; sep = 1e-3; end
        ux = dx / sep;  uy = dy / sep;
        % Shuttle velocity direction (along loop path, approx)
        closing = spd_s;         % Conservative: full speed toward ped

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

        % Severity
        if TTC < cfg.ttc_high
            sev = 'high';
        elseif TTC < cfg.ttc_med
            sev = 'medium';
        else
            sev = 'low';
        end

        % Only log medium/high or very close separations
        if strcmp(sev,'low') && sep > cfg.ped_detect_radius * 0.6
            continue
        end

        enc.t          = t;
        enc.shuttle_id = i;
        enc.enc_type   = 'ped';
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

        if TTC < cfg.ttc_high
            sev = 'high';
        elseif TTC < cfg.ttc_med
            sev = 'medium';
        else
            sev = 'low';
        end

        if strcmp(sev,'low'); continue; end

        enc.t          = t;
        enc.shuttle_id = i;
        enc.enc_type   = 'veh';
        enc.TTC        = TTC;
        enc.PET        = PET;
        enc.min_sep    = sep;
        enc.severity   = sev;
        encounters(end+1) = enc; %#ok<AGROW>
    end
end
end
