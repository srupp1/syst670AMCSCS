function osv = osv_all(varargin)
% osv_all  Objective System Verification — all five OSV tests
%
% Runs a single Monte Carlo simulation and evaluates each of the five
% objective system verification criteria.  All OSV tests share the same
% simulation run to avoid redundant computation.
%
% OSV thresholds (from test plan — stricter than simulation cfg.kpp):
%   PCR       <= 0.5  high-severity conflicts per 1,000 ped encounters  (0.0005)
%   IVCR      <= 0.3  high-severity conflicts per 1,000 veh encounters  (0.0003)
%   ATD mean  <= 10%  of free-flow; P95 delay <= 40%
%   SAA       recall >= 0.98; pred_err <= 0.5m; latency <= 200ms
%   UTI       >= 0.80
%
% Usage:
%   osv = osv_all              % 100 reps (default)
%   osv = osv_all('reps', 50)  % custom rep count
%
% Returns struct with fields: pcr, ivcr, atd, saa, uti
%   Each is a result struct: id, name, pass, reasons, metrics

p = inputParser;
addParameter(p, 'reps', 100, @(x) isnumeric(x) && x >= 10);
parse(p, varargin{:});
N_REPS = p.Results.reps;

fprintf('\n=====================================================\n');
fprintf(' OSV Tests: Objective System Verification (all 5)\n');
fprintf(' Monte Carlo: %d replications\n', N_REPS);
fprintf('=====================================================\n\n');

%% OSV-specific pass/fail thresholds
OSV_PCR_MAX  = 0.5  / 1000;   % 0.0005
OSV_IVCR_MAX = 0.3  / 1000;   % 0.0003
OSV_ATD_MEAN = 10.0;           % % delay, mean
OSV_ATD_P95  = 40.0;           % % delay, 95th percentile
OSV_SAA_RECALL = 0.98;
OSV_SAA_PRED   = 0.5;          % m at 3s horizon
OSV_SAA_LAT    = 0.200;        % s = 200 ms
OSV_UTI_MIN    = 0.80;

%% Setup
cfg               = getDefaultConfig();
cfg.n_replications = N_REPS;
cfg.base_seed     = 42;

try
    env = loadEnvironment('G.mat', cfg);
catch ME
    err = sprintf('loadEnvironment failed: %s', ME.message);
    fail = struct('pass',false,'reasons',{{err}});
    osv.pcr  = makeResult('OSV-PCR-01',  'pedestrianConflictRate',   fail);
    osv.ivcr = makeResult('OSV-IVCR-01', 'interVehicleConflictRate', fail);
    osv.atd  = makeResult('OSV-ATD-01',  'averageTimeDelay',         fail);
    osv.saa  = makeResult('OSV-SAA-01',  'situationalAwarenessAcc',  fail);
    osv.uti  = makeResult('OSV-UTI-01',  'userTrustIndex',           fail);
    return;
end

%% Run Monte Carlo
enc_all  = cell(N_REPS,1);
trip_all = cell(N_REPS,1);
perc_all = cell(N_REPS,1);
jerk_all = cell(N_REPS,1);

tic;
for rep = 1:N_REPS
    rng(cfg.base_seed + rep - 1);
    state = initReplication(env, cfg);

    encounters = struct('t',{},'shuttle_id',{},'enc_type',{}, ...
                        'TTC',{},'PET',{},'min_sep',{},'severity',{});
    trips      = struct('shuttle_id',{},'leg',{},'start_node',{}, ...
                        'end_node',{},'actual_t',{},'baseline_t',{}, ...
                        'delay_pct',{},'t',{});
    perception = struct('t',{},'shuttle_id',{},'agent_type',{}, ...
                        'true_x',{},'true_y',{},'det_x',{},'det_y',{}, ...
                        'detected',{},'pred_err',{},'latency',{});

    for k = 1:cfg.n_steps
        t_sim = cfg.t_start + (k-1)*cfg.dt;
        [state, enc_k, trip_k, perc_k] = stepSimulation(state, env, cfg, t_sim);
        if ~isempty(enc_k),  encounters = [encounters, enc_k];   end %#ok<AGROW>
        if ~isempty(trip_k), trips      = [trips,      trip_k];  end %#ok<AGROW>
        if ~isempty(perc_k), perception = [perception, perc_k];  end %#ok<AGROW>
    end

    enc_all{rep}  = encounters;
    trip_all{rep} = trips;
    perc_all{rep} = perception;

    js(cfg.n_shuttles) = struct('rms_jerk',0,'rms_brake_jerk',0);
    for i = 1:cfg.n_shuttles
        sh = state.shuttles(i);
        if sh.jerk_n       > 0, js(i).rms_jerk       = sqrt(sh.jerk_sq_sum       / sh.jerk_n);       end
        if sh.brake_jerk_n > 0, js(i).rms_brake_jerk = sqrt(sh.brake_jerk_sq_sum / sh.brake_jerk_n); end
    end
    jerk_all{rep} = js;
    clear js;

    if mod(rep, max(1,floor(N_REPS/5))) == 0
        fprintf('  Completed %d/%d reps  (%.1f s)\n', rep, N_REPS, toc);
    end
end
fprintf('\nMC complete: %.1f s  (%.2f s/rep)\n\n', toc, toc/N_REPS);

kpps = computeKPPs(enc_all, trip_all, perc_all, jerk_all, cfg, env);

%% ── OSV-PCR-01: Pedestrian Conflict Rate ─────────────────────────────────
fprintf('--- OSV-PCR-01: Pedestrian Conflict Rate ---\n');
pcr_fr = {};
pcr_pass = kpps.PCR.ci95_hi <= OSV_PCR_MAX;
fprintf('  PCR mean  = %.6f  (threshold <= %.6f)\n', kpps.PCR.mean, OSV_PCR_MAX);
fprintf('  95%% CI   = [%.6f, %.6f]\n', kpps.PCR.ci95_lo, kpps.PCR.ci95_hi);
if ~pcr_pass
    pcr_fr{end+1} = sprintf('PCR CI upper bound %.6f > OSV threshold %.6f', ...
        kpps.PCR.ci95_hi, OSV_PCR_MAX);
end
fprintf('  OSV-PCR-01: %s\n\n', tf2str(pcr_pass));

%% ── OSV-IVCR-01: Inter-Vehicle Conflict Rate ─────────────────────────────
fprintf('--- OSV-IVCR-01: Inter-Vehicle Conflict Rate ---\n');
ivcr_fr = {};
ivcr_pass = kpps.IVCR.ci95_hi <= OSV_IVCR_MAX;
fprintf('  IVCR mean = %.6f  (threshold <= %.6f)\n', kpps.IVCR.mean, OSV_IVCR_MAX);
fprintf('  95%% CI   = [%.6f, %.6f]\n', kpps.IVCR.ci95_lo, kpps.IVCR.ci95_hi);
if ~ivcr_pass
    ivcr_fr{end+1} = sprintf('IVCR CI upper bound %.6f > OSV threshold %.6f', ...
        kpps.IVCR.ci95_hi, OSV_IVCR_MAX);
end
fprintf('  OSV-IVCR-01: %s\n\n', tf2str(ivcr_pass));

%% ── OSV-ATD-01: Average Time Delay ──────────────────────────────────────
fprintf('--- OSV-ATD-01: Average Time Delay ---\n');
atd_fr = {};

% Mean delay at 95% CI (conservative upper bound)
atd_mean_pass = kpps.ATD.ci95_hi <= OSV_ATD_MEAN;
fprintf('  ATD mean  = %.3f%%  (threshold <= %.1f%%)\n', kpps.ATD.mean, OSV_ATD_MEAN);
fprintf('  95%% CI   = [%.3f%%, %.3f%%]\n', kpps.ATD.ci95_lo, kpps.ATD.ci95_hi);
if ~atd_mean_pass
    atd_fr{end+1} = sprintf('ATD CI upper bound %.3f%% > OSV mean threshold %.1f%%', ...
        kpps.ATD.ci95_hi, OSV_ATD_MEAN);
end

% 95th percentile delay across all trips
all_delay = [];
for r = 1:N_REPS
    if ~isempty(trip_all{r}) && numel(trip_all{r}) > 0
        all_delay = [all_delay, [trip_all{r}.delay_pct]]; %#ok<AGROW>
    end
end
if isempty(all_delay)
    p95_delay = 0;
    fprintf('  P95 delay: N/A (no trips recorded)\n');
else
    p95_delay = prctile(all_delay, 95);
    fprintf('  P95 delay = %.3f%%  (threshold <= %.1f%%,  n=%d trips)\n', ...
        p95_delay, OSV_ATD_P95, numel(all_delay));
end
atd_p95_pass = p95_delay <= OSV_ATD_P95;
if ~atd_p95_pass
    atd_fr{end+1} = sprintf('P95 delay %.3f%% > OSV P95 threshold %.1f%%', p95_delay, OSV_ATD_P95);
end

atd_pass = atd_mean_pass && atd_p95_pass;
fprintf('  OSV-ATD-01: %s\n\n', tf2str(atd_pass));

%% ── OSV-SAA-01: Situational Awareness Accuracy ───────────────────────────
fprintf('--- OSV-SAA-01: Situational Awareness Accuracy ---\n');
saa_fr = {};

saa_recall_pass = kpps.SAA_recall.ci95_lo >= OSV_SAA_RECALL;
fprintf('  Detection recall mean = %.5f  (threshold >= %.2f)\n', ...
    kpps.SAA_recall.mean, OSV_SAA_RECALL);
fprintf('  95%% CI = [%.5f, %.5f]\n', kpps.SAA_recall.ci95_lo, kpps.SAA_recall.ci95_hi);
if ~saa_recall_pass
    saa_fr{end+1} = sprintf('SAA recall CI lower %.5f < OSV threshold %.2f', ...
        kpps.SAA_recall.ci95_lo, OSV_SAA_RECALL);
end

% Prediction error and latency from aggregated perc_all
all_pred  = [];
all_lat   = [];
for r = 1:N_REPS
    if ~isempty(perc_all{r}) && numel(perc_all{r}) > 0
        all_pred = [all_pred, [perc_all{r}.pred_err]]; %#ok<AGROW>
        all_lat  = [all_lat,  [perc_all{r}.latency]];  %#ok<AGROW>
    end
end
if isempty(all_pred)
    mean_pred = 0; mean_lat = 0;
    fprintf('  No perception events recorded\n');
else
    mean_pred = mean(all_pred);
    mean_lat  = mean(all_lat);
    n_perc    = numel(all_pred);
    ci_pred   = 1.96 * std(all_pred) / sqrt(n_perc);
    ci_lat    = 1.96 * std(all_lat)  / sqrt(n_perc);
    fprintf('  Pred error mean = %.4f m  (threshold <= %.1f m)  CI=[%.4f, %.4f]\n', ...
        mean_pred, OSV_SAA_PRED, mean_pred-ci_pred, mean_pred+ci_pred);
    fprintf('  Latency   mean = %.4f s  (threshold <= %.3f s)  CI=[%.4f, %.4f]\n', ...
        mean_lat, OSV_SAA_LAT, mean_lat-ci_lat, mean_lat+ci_lat);
end

pred_pass = (mean_pred + 1.96*std(all_pred)/sqrt(max(1,numel(all_pred)))) <= OSV_SAA_PRED;
lat_pass  = (mean_lat  + 1.96*std(all_lat) /sqrt(max(1,numel(all_lat))))  <= OSV_SAA_LAT;
if ~pred_pass
    saa_fr{end+1} = sprintf('Pred error CI upper %.4f m > OSV threshold %.1f m', ...
        mean_pred + 1.96*std(all_pred)/sqrt(max(1,numel(all_pred))), OSV_SAA_PRED);
end
if ~lat_pass
    saa_fr{end+1} = sprintf('Latency CI upper %.4f s > OSV threshold %.3f s', ...
        mean_lat + 1.96*std(all_lat)/sqrt(max(1,numel(all_lat))), OSV_SAA_LAT);
end

saa_pass = saa_recall_pass && pred_pass && lat_pass;
fprintf('  OSV-SAA-01: %s\n\n', tf2str(saa_pass));

%% ── OSV-UTI-01: User Trust Index ─────────────────────────────────────────
fprintf('--- OSV-UTI-01: User Trust Index ---\n');
uti_fr = {};
uti_pass = kpps.UTI.ci95_lo >= OSV_UTI_MIN;
fprintf('  UTI mean  = %.4f  (threshold >= %.2f)\n', kpps.UTI.mean, OSV_UTI_MIN);
fprintf('  95%% CI   = [%.4f, %.4f]\n', kpps.UTI.ci95_lo, kpps.UTI.ci95_hi);
if ~uti_pass
    uti_fr{end+1} = sprintf('UTI CI lower %.4f < OSV threshold %.2f', ...
        kpps.UTI.ci95_lo, OSV_UTI_MIN);
end
fprintf('  OSV-UTI-01: %s\n\n', tf2str(uti_pass));

%% ── Pack results ─────────────────────────────────────────────────────────
osv.pcr  = struct('id','OSV-PCR-01',  'name','pedestrianConflictRate',   ...
    'pass',pcr_pass,  'reasons',{pcr_fr},  ...
    'metrics',struct('mean',kpps.PCR.mean,  'ci95_lo',kpps.PCR.ci95_lo,  'ci95_hi',kpps.PCR.ci95_hi,  'threshold',OSV_PCR_MAX));
osv.ivcr = struct('id','OSV-IVCR-01', 'name','interVehicleConflictRate', ...
    'pass',ivcr_pass, 'reasons',{ivcr_fr}, ...
    'metrics',struct('mean',kpps.IVCR.mean, 'ci95_lo',kpps.IVCR.ci95_lo, 'ci95_hi',kpps.IVCR.ci95_hi, 'threshold',OSV_IVCR_MAX));
osv.atd  = struct('id','OSV-ATD-01',  'name','averageTimeDelay',         ...
    'pass',atd_pass,  'reasons',{atd_fr},  ...
    'metrics',struct('mean',kpps.ATD.mean,  'ci95_lo',kpps.ATD.ci95_lo,  'ci95_hi',kpps.ATD.ci95_hi,  'p95',p95_delay, 'threshold_mean',OSV_ATD_MEAN,'threshold_p95',OSV_ATD_P95));
osv.saa  = struct('id','OSV-SAA-01',  'name','situationalAwarenessAcc',  ...
    'pass',saa_pass,  'reasons',{saa_fr},  ...
    'metrics',struct('recall',kpps.SAA_recall.mean, 'pred_err',mean_pred, 'latency_s',mean_lat));
osv.uti  = struct('id','OSV-UTI-01',  'name','userTrustIndex',           ...
    'pass',uti_pass,  'reasons',{uti_fr},  ...
    'metrics',struct('mean',kpps.UTI.mean,  'ci95_lo',kpps.UTI.ci95_lo,  'ci95_hi',kpps.UTI.ci95_hi,  'threshold',OSV_UTI_MIN));
end

% ── Helpers ──────────────────────────────────────────────────────────────────
function r = makeResult(id, name, fail)
    r = struct('id',id,'name',name,'pass',fail.pass,'reasons',{fail.reasons},'metrics',struct());
end

function s = tf2str(v)
    if v; s = 'PASS'; else; s = 'FAIL'; end
end
