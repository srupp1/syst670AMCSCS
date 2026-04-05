% main.m  –  ACMSCS Simulation Entry Point
% Autonomous Campus Mobility Safety & Coordination System
% UMBC Campus  |  KSTM Labs
%
% Simulation lifecycle (per design doc Section 2.3):
%   Idle → Configure Scenario → Initialize Replication →
%   Running Time Steps → Collecting Metrics →
%   Aggregating Results → Verifying KPPs → Reporting → End
%
% Usage:
%   main                         % Run with default config (100 reps)
%   cfg = getDefaultConfig();
%   cfg.n_replications = 1000;   % Override, then run main

clear; clc; close all;

%% ── Idle → Configure Scenario ──────────────────────────────────────────
if ~exist('cfg','var')
    cfg = getDefaultConfig();
end
env = loadEnvironment('G.mat', cfg);

%% ── Initialize dashboard ────────────────────────────────────────────────
dash = initDashboard(env, cfg);

% How often to refresh the map during a replication (~20 frames/rep)
update_interval = max(1, floor(cfg.n_steps / 20));

%% Allocate log storage (SIM-MET-001)
enc_all  = cell(cfg.n_replications, 1);
trip_all = cell(cfg.n_replications, 1);
perc_all = cell(cfg.n_replications, 1);
jerk_all = cell(cfg.n_replications, 1);

% Running KPP value accumulators (one scalar per completed replication)
pcr_reps  = nan(cfg.n_replications, 1);
ivcr_reps = nan(cfg.n_replications, 1);
atd_reps  = nan(cfg.n_replications, 1);
saa_reps  = nan(cfg.n_replications, 1);
uti_reps  = nan(cfg.n_replications, 1);

fprintf('Starting Monte Carlo simulation (%d replications)...\n\n', cfg.n_replications);
tic;

%% ── Monte Carlo loop ────────────────────────────────────────────────────
for rep = 1:cfg.n_replications

    % ── Initialize Replication (SIM-INT-001, SIM-INT-002) ────────────────
    rng(cfg.base_seed + rep - 1);
    state = initReplication(env, cfg);

    encounters = struct('t',{},'shuttle_id',{},'enc_type',{},...
                        'TTC',{},'PET',{},'min_sep',{},'severity',{});
    trips      = struct('shuttle_id',{},'leg',{},'start_node',{},'end_node',{},...
                        'actual_t',{},'baseline_t',{},'delay_pct',{},'t',{});
    perception = struct('t',{},'shuttle_id',{},'agent_type',{},...
                        'true_x',{},'true_y',{},'det_x',{},'det_y',{},...
                        'detected',{},'pred_err',{},'latency',{});

    % ── Running Time Steps (SIM-RUN-001) ─────────────────────────────────
    for k = 1:cfg.n_steps
        t_sim = cfg.t_start + (k - 1) * cfg.dt;

        [state, enc_k, trip_k, perc_k] = stepSimulation(state, env, cfg, t_sim);

        % ── Collecting Metrics (SIM-MET-001) ─────────────────────────────
        if ~isempty(enc_k)
            encounters = [encounters, enc_k]; %#ok<AGROW>
        end
        if ~isempty(trip_k)
            trips = [trips, trip_k]; %#ok<AGROW>
        end
        if ~isempty(perc_k)
            perception = [perception, perc_k]; %#ok<AGROW>
        end

        % ── Periodic map refresh ─────────────────────────────────────────
        if mod(k, update_interval) == 0 && ishandle(dash.fig)
            dash = updateDashboard(dash, state, env, cfg, rep, k, toc, ...
                numel(encounters), numel(trips), []);
        end
    end

    enc_all{rep}  = encounters;
    trip_all{rep} = trips;
    perc_all{rep} = perception;

    % ── Extract jerk stats from final shuttle state ───────────────────────
    jerk_stats(cfg.n_shuttles) = struct('rms_jerk',0,'rms_brake_jerk',0);
    for i = 1:cfg.n_shuttles
        sh = state.shuttles(i);
        if sh.jerk_n > 0
            jerk_stats(i).rms_jerk = sqrt(sh.jerk_sq_sum / sh.jerk_n);
        else
            jerk_stats(i).rms_jerk = 0;
        end
        if sh.brake_jerk_n > 0
            jerk_stats(i).rms_brake_jerk = sqrt(sh.brake_jerk_sq_sum / sh.brake_jerk_n);
        else
            jerk_stats(i).rms_brake_jerk = 0;
        end
    end
    jerk_all{rep} = jerk_stats;

    % ── Compute quick per-rep KPP estimates for dashboard ────────────────
    enc_r  = enc_all{rep};
    trip_r = trip_all{rep};
    perc_r = perc_all{rep};

    if ~isempty(enc_r) && numel(enc_r) > 0
        enc_types = {enc_r.enc_type};
        ped_enc   = enc_r(strcmp(enc_types,'ped'));
        veh_enc   = enc_r(strcmp(enc_types,'veh'));
        if ~isempty(ped_enc)
            sev = {ped_enc.severity};
            pcr_reps(rep) = sum(strcmp(sev,'high')|strcmp(sev,'medium')) / max(1,numel(ped_enc));
        else
            pcr_reps(rep) = 0;
        end
        if ~isempty(veh_enc)
            sev = {veh_enc.severity};
            ivcr_reps(rep) = sum(strcmp(sev,'high')|strcmp(sev,'medium')) / max(1,numel(veh_enc));
        else
            ivcr_reps(rep) = 0;
        end
    else
        pcr_reps(rep) = 0;  ivcr_reps(rep) = 0;
    end

    atd_reps(rep) = 0;
    if ~isempty(trip_r) && numel(trip_r) > 0
        atd_reps(rep) = mean([trip_r.delay_pct]);
    end

    saa_reps(rep) = cfg.detect_prob;
    if ~isempty(perc_r) && numel(perc_r) > 0
        saa_reps(rep) = mean([perc_r.detected]);
    end

    rj = mean([jerk_stats.rms_jerk]);
    rb = mean([jerk_stats.rms_brake_jerk]);
    nj = max(0, min(1, (rj - 1.0) / 2.0));
    nb = max(0, min(1, (rb - 1.5) / 2.5));
    uti_reps(rep) = max(0, 1 - 0.40*nj - 0.35*nb ...
        - 0.25*min(1, pcr_reps(rep)/cfg.kpp.pcr_max));

    % Build running-mean struct for dashboard
    kpp_running.PCR       = mean(pcr_reps(1:rep),  'omitnan');
    kpp_running.IVCR      = mean(ivcr_reps(1:rep), 'omitnan');
    kpp_running.ATD       = mean(atd_reps(1:rep),  'omitnan');
    kpp_running.SAA_recall = mean(saa_reps(1:rep), 'omitnan');
    kpp_running.UTI       = mean(uti_reps(1:rep),  'omitnan');

    if ishandle(dash.fig)
        dash = updateDashboard(dash, state, env, cfg, rep, cfg.n_steps, toc, ...
            numel(enc_all{rep}), numel(trip_all{rep}), kpp_running);
    end

    % Console progress every 10%
    if mod(rep, max(1, floor(cfg.n_replications/10))) == 0
        elapsed = toc;
        eta     = elapsed / rep * (cfg.n_replications - rep);
        fprintf('  Rep %4d/%d  |  %.1f s elapsed  |  ETA %.0f s\n', ...
            rep, cfg.n_replications, elapsed, eta);
    end
end

elapsed = toc;
fprintf('\nAll replications complete in %.1f s (%.1f s/rep)\n\n', ...
    elapsed, elapsed/cfg.n_replications);

%% ── Aggregating Results (SIM-AGG-001) ───────────────────────────────────
fprintf('Aggregating results...\n');
kpps = computeKPPs(enc_all, trip_all, perc_all, jerk_all, cfg, env);

%% ── Verifying KPPs + Reporting (SIM-KPP-001, SIM-RPT-001) ──────────────
generateReport(kpps, cfg);

%% ── Finalize dashboard ───────────────────────────────────────────────────
if ishandle(dash.fig)
    finalizeDashboard(dash, kpps, cfg);
end

%% ── End (SIM-END-001) ────────────────────────────────────────────────────
fprintf('Simulation complete.\n');
