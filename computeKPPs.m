function kpps = computeKPPs(enc_all, trip_all, perc_all, jerk_all, cfg, env)
% computeKPPs  Aggregate Monte Carlo results and compute all KPPs with 95% CIs.
%
% KPP result struct fields (SIM-IIF-004):
%   PCR, IVCR, ATD, SAA_recall, SAA_pred_err, SAA_latency, UTI
%   Each field is a struct: .mean  .std  .ci95_lo  .ci95_hi  .threshold  .pass

n = cfg.n_replications;

pcr_rep    = zeros(n,1);
ivcr_rep   = zeros(n,1);
atd_rep    = zeros(n,1);
recall_rep = zeros(n,1);
pred_rep   = zeros(n,1);
lat_rep    = zeros(n,1);
uti_rep    = zeros(n,1);

for r = 1:n
    enc  = enc_all{r};
    trip = trip_all{r};
    perc = perc_all{r};
    jerk = jerk_all{r};

    %% PCR — Pedestrian Conflict Rate
    % = (# high/medium ped conflicts) / (total ped encounters)
    if ~isempty(enc) && ~isempty(fieldnames(enc)) && numel(enc) > 0
        enc_types = {enc.enc_type};
        ped_mask  = strcmp(enc_types, 'ped');
        veh_mask  = strcmp(enc_types, 'veh');
        ped_enc   = enc(ped_mask);
        veh_enc   = enc(veh_mask);

        % Deduplicate: keep worst severity per unique (shuttle_id, agent_id) pair
        ped_conf  = deduplicateConflicts(ped_enc);
        veh_conf  = deduplicateConflicts(veh_enc);
    else
        ped_enc = [];  veh_enc = [];
        ped_conf = struct('n_unique',0,'n_conflict',0);
        veh_conf = struct('n_unique',0,'n_conflict',0);
    end

    pcr_rep(r)  = ped_conf.n_conflict / max(1, ped_conf.n_unique);
    ivcr_rep(r) = veh_conf.n_conflict / max(1, veh_conf.n_unique);

    %% ATD — Average Trip Delay [%]
    % = mean((actual_time - baseline_time) / baseline_time * 100)
    if ~isempty(trip) && numel(trip) > 0
        atd_rep(r) = mean([trip.delay_pct]);
    else
        atd_rep(r) = 0;
    end

    %% SAA — Situational Awareness Accuracy
    % Recall  = mean(detected flag) across all perception events
    % Pred err = mean(||predicted_pos - true_future_pos||) [m]
    % Latency  = mean(perception latency) [s]
    if ~isempty(perc) && numel(perc) > 0
        recall_rep(r) = mean([perc.detected]);
        pred_rep(r)   = mean([perc.pred_err]);
        lat_rep(r)    = mean([perc.latency]);
    else
        recall_rep(r) = cfg.detect_prob;
        pred_rep(r)   = 0;
        lat_rep(r)    = cfg.latency_mean;
    end

    %% UTI — User Trust Index
    % Based on Table 2-4 metrics: Longitudinal Jerk, Braking Smoothness,
    % Behavior Consistency.
    %
    % RMS jerk per shuttle (m/s^3) is accumulated in updateShuttles via:
    %   jerk = (accel_k - accel_{k-1}) / dt   [true d^2v/dt^2]
    %   rms_jerk = sqrt(mean(jerk^2))
    %
    % Thresholds calibrated to the simulation's physical jerk range.
    % ISO 2631 values (1-4 m/s^3) assume sub-second sampling and cannot be
    % applied directly.  At dt=10 s, jerk = d^2v/dt^2 scales as speed_std/dt^2,
    % giving typical RMS values ~0.003 m/s^3.  Max possible jerk is bounded by
    % the speed clamp range: (6-1)/dt^2 = 0.05 m/s^3.  Thresholds below place
    % normal operation near norm=0.2 and worst-case near norm=1.
    jerk_ref      = cfg.speed_std / cfg.dt^2;   % ~0.0015 for defaults
    jerk_comfort  = 0.5 * jerk_ref;   jerk_max  = 8.0 * jerk_ref;
    brake_comfort = 0.4 * jerk_ref;   brake_max = 6.0 * jerk_ref;

    if ~isempty(jerk) && numel(jerk) > 0
        total_jerk_sq  = sum([jerk.rms_jerk].^2 .* max([jerk.jerk_n], 0));
        total_jerk_n   = sum(max([jerk.jerk_n], 0));
        total_brake_sq = sum([jerk.rms_brake_jerk].^2 .* max([jerk.brake_jerk_n], 0));
        total_brake_n  = sum(max([jerk.brake_jerk_n], 0));
        mean_rms_jerk  = sqrt(total_jerk_sq  / max(total_jerk_n,  1));
        mean_rms_brake = sqrt(total_brake_sq / max(total_brake_n, 1));
    else
        mean_rms_jerk  = 0;
        mean_rms_brake = 0;
    end

    % Normalise each component to [0,1] linearly between comfort and max
    norm_jerk  = max(0, min(1, (mean_rms_jerk  - jerk_comfort)  / (jerk_max  - jerk_comfort)));
    norm_brake = max(0, min(1, (mean_rms_brake - brake_comfort) / (brake_max - brake_comfort)));

    % Behavior consistency: penalise high conflict rate (proxy for
    % unpredictable shuttle behavior near pedestrians)
    consistency_penalty = min(1, pcr_rep(r) / cfg.kpp.pcr_max);

    uti_rep(r) = max(0, 1 - cfg.uti_w_jerk*norm_jerk ...
                          - cfg.uti_w_brake*norm_brake ...
                          - cfg.uti_w_consistency*consistency_penalty);
end

%% Aggregate: mean, std, 95% CI, pass/fail  (SIM-AGG-001, SIM-CAP-012)
kpps.PCR          = aggKPP(pcr_rep,    cfg.kpp.pcr_max,  'le');
kpps.IVCR         = aggKPP(ivcr_rep,   cfg.kpp.ivcr_max, 'le');
kpps.ATD          = aggKPP(atd_rep,    cfg.kpp.atd_max,  'le');
kpps.SAA_recall   = aggKPP(recall_rep, cfg.kpp.saa_min,  'ge');
kpps.SAA_pred_err = aggKPP(pred_rep,   1.0,              'le');  % info only
kpps.SAA_latency  = aggKPP(lat_rep,    0.1,              'le');  % info only
kpps.UTI          = aggKPP(uti_rep,    cfg.kpp.uti_min,  'ge');
end

% -------------------------------------------------------------------------
function r = deduplicateConflicts(enc_arr)
% Per unique (shuttle_id, agent_id) pair keep worst severity; return counts.
% Severity rank: high=2, medium=1, low=0.
    if isempty(enc_arr)
        r = struct('n_unique', 0, 'n_conflict', 0);
        return;
    end
    sev_rank = 2*strcmp({enc_arr.severity},'high') + strcmp({enc_arr.severity},'medium');
    keys = [[enc_arr.shuttle_id]', [enc_arr.agent_id]'];
    [~, ~, ic] = unique(keys, 'rows');
    n_unique = max(ic);
    worst = zeros(n_unique, 1);
    for u = 1:n_unique
        worst(u) = max(sev_rank(ic == u));
    end
    r = struct('n_unique', n_unique, 'n_conflict', sum(worst >= 1));
end

% -------------------------------------------------------------------------
function r = aggKPP(vals, threshold, direction)
% Compute mean, std, 95% CI, and pass/fail for one KPP.
% CI bound used for pass/fail is the conservative side:
%   'le' (must be ≤ threshold): use ci95_hi
%   'ge' (must be ≥ threshold): use ci95_lo
    r.mean      = mean(vals);
    r.std       = std(vals);
    n           = numel(vals);
    half_width  = 1.960 * r.std / sqrt(n);   % z = 1.96 for 95% CI
    r.ci95_lo   = r.mean - half_width;
    r.ci95_hi   = r.mean + half_width;
    r.threshold = threshold;
    if strcmp(direction, 'le')
        r.pass = r.ci95_hi <= threshold;
    else
        r.pass = r.ci95_lo >= threshold;
    end
end
