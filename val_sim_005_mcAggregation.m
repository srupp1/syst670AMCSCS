function result = val_sim_005_mcAggregation()
% VAL-SIM-005: Monte Carlo Statistical Aggregation Validation
%
% Validates that computeKPPs correctly aggregates per-replication data
% into mean, std, and 95% CI using synthetic datasets whose statistical
% properties are known exactly.
%
% Method: build enc_all / trip_all / perc_all / jerk_all directly with
% deterministic per-rep values, then verify computeKPPs matches analytical
% computations of mean ± 1.96×std/sqrt(n) to within 1%.
%
% Requirements: SIM-CAP-012, SIM-AGG-001, SIM-KPP-001
%
% Pass criteria (per test plan):
%   Mean value error         <= 1%
%   CI bound error           <= 1% of analytical CI values

fprintf('\n=======================================================\n');
fprintf(' VAL-SIM-005: Monte Carlo Statistical Aggregation Validation\n');
fprintf('=======================================================\n');

passed       = true;
fail_reasons = {};

cfg = getDefaultConfig();
try
    env = loadEnvironment('G.mat', cfg);
catch ME
    result = struct('id','VAL-SIM-005','name','mcAggregation','pass',false, ...
        'reasons',{{sprintf('loadEnvironment failed: %s', ME.message)}});
    fprintf('VAL-SIM-005 RESULT: FAIL\n  - %s\n\n', result.reasons{1});
    return;
end

N_REPS = 50;
cfg.n_replications = N_REPS;

%% ── Design synthetic per-rep values ─────────────────────────────────────
% PCR: alternate 0.03 / 0.07  → mean=0.05, std=0.02
% IVCR: alternate 0.01 / 0.05 → mean=0.03, std=0.02
% ATD: alternate 5% / 15%     → mean=10%, std=5%
% SAA recall: all reps = 0.92  → mean=0.92, std=0
% UTI: depends on jerk & PCR, computed analytically after construction

pcr_target  = @(r) 0.03 + 0.04*mod(r,2);     % 0.03 or 0.07
ivcr_target = @(r) 0.01 + 0.04*mod(r,2);     % 0.01 or 0.05
atd_target  = @(r) 5    + 10  *mod(r,2);     % 5% or 15%
rec_target  = 0.92;

% Known analytical summary statistics
pcr_vals  = arrayfun(pcr_target,  1:N_REPS);
ivcr_vals = arrayfun(ivcr_target, 1:N_REPS);
atd_vals  = arrayfun(atd_target,  1:N_REPS);
rec_vals  = repmat(rec_target, 1, N_REPS);

ana = struct();
ana.PCR  = aggAnalytical(pcr_vals,  cfg.kpp.pcr_max,  'le');
ana.IVCR = aggAnalytical(ivcr_vals, cfg.kpp.ivcr_max, 'le');
ana.ATD  = aggAnalytical(atd_vals,  cfg.kpp.atd_max,  'le');
ana.SAA  = aggAnalytical(rec_vals,  cfg.kpp.saa_min,  'ge');

%% ── Build synthetic datasets ─────────────────────────────────────────────
enc_all  = cell(N_REPS,1);
trip_all = cell(N_REPS,1);
perc_all = cell(N_REPS,1);
jerk_all = cell(N_REPS,1);

% Fixed encounter count per rep: 100 ped enc, 100 veh enc
N_PED_ENC = 100;
N_VEH_ENC = 100;
% Fixed trip count per rep: 10 trips per shuttle
N_TRIPS_PER_REP = cfg.n_shuttles * 10;
% Fixed perception events per rep: 50
N_PERC = 50;
% Fixed jerk stats (low jerk → UTI ≈ 1)
RMS_JERK  = 0.5;    % m/s³ — below comfort threshold of 1.0
RMS_BRAKE = 0.8;    % m/s³ — below comfort threshold of 1.5

for r = 1:N_REPS
    pcr_r  = pcr_target(r);
    ivcr_r = ivcr_target(r);
    atd_r  = atd_target(r);

    %% Encounters
    n_ped_high = round(pcr_r  * N_PED_ENC);
    n_veh_high = round(ivcr_r * N_VEH_ENC);
    enc = makeEncounters(N_PED_ENC, N_VEH_ENC, n_ped_high, n_veh_high);
    enc_all{r} = enc;

    %% Trips  (delay_pct given directly; actual_t and baseline_t consistent)
    baseline_t = 120.0;   % s per leg (arbitrary fixed value)
    actual_t   = baseline_t * (1 + atd_r/100);
    tr = struct('shuttle_id',{},'leg',{},'start_node',{},'end_node',{}, ...
                'actual_t',{},'baseline_t',{},'delay_pct',{},'t',{});
    for j = 1:N_TRIPS_PER_REP
        tr(j).shuttle_id  = 1;
        tr(j).leg         = j;
        tr(j).start_node  = 1;
        tr(j).end_node    = 2;
        tr(j).actual_t    = actual_t;
        tr(j).baseline_t  = baseline_t;
        tr(j).delay_pct   = atd_r;    % use exact value; bypass 100*(act-base)/base rounding
        tr(j).t           = j * 100;
    end
    trip_all{r} = tr;

    %% Perception (detection rate = rec_target)
    n_det = round(rec_target * N_PERC);
    pr = struct('t',{},'shuttle_id',{},'agent_type',{}, ...
                'true_x',{},'true_y',{},'det_x',{},'det_y',{}, ...
                'detected',{},'pred_err',{},'latency',{});
    for j = 1:N_PERC
        pr(j).t           = j;
        pr(j).shuttle_id  = 1;
        pr(j).agent_type  = 'ped';
        pr(j).true_x      = 5; pr(j).true_y = 0;
        pr(j).det_x       = 5; pr(j).det_y  = 0;
        pr(j).detected    = (j <= n_det);
        pr(j).pred_err    = 0.3;
        pr(j).latency     = cfg.latency_mean;
    end
    perc_all{r} = pr;

    %% Jerk stats  (RMS_JERK and RMS_BRAKE per shuttle, same each rep)
    js(cfg.n_shuttles) = struct('rms_jerk',0,'rms_brake_jerk',0);
    for i = 1:cfg.n_shuttles
        js(i).rms_jerk       = RMS_JERK;
        js(i).rms_brake_jerk = RMS_BRAKE;
    end
    jerk_all{r} = js;
end

%% Analytical UTI (same formula as computeKPPs)
jerk_comfort=1.0; jerk_max=3.0; brake_comfort=1.5; brake_max=4.0;
norm_jerk  = max(0, min(1, (RMS_JERK  - jerk_comfort)  / (jerk_max  - jerk_comfort)));
norm_brake = max(0, min(1, (RMS_BRAKE - brake_comfort) / (brake_max - brake_comfort)));
uti_vals = zeros(1,N_REPS);
for r = 1:N_REPS
    consistency = min(1, pcr_target(r) / cfg.kpp.pcr_max);
    uti_vals(r) = max(0, 1 - 0.40*norm_jerk - 0.35*norm_brake - 0.25*consistency);
end
ana.UTI = aggAnalytical(uti_vals, cfg.kpp.uti_min, 'ge');

%% Run computeKPPs
kpps = computeKPPs(enc_all, trip_all, perc_all, jerk_all, cfg, env);

%% Compare analytical vs computed
fprintf('\n  %-12s  %10s  %10s  %10s  %10s  %10s  %s\n', ...
    'KPP', 'Ana.Mean', 'Sim.Mean', 'MeanErr%', 'CI_lo err%', 'CI_hi err%', 'Pass?');
fprintf('  %s\n', repmat('-',1,80));

KPP_MAP = {'PCR','IVCR','ATD','SAA_recall','UTI'};
ANA_MAP = {'PCR','IVCR','ATD','SAA','UTI'};

for i = 1:numel(KPP_MAP)
    sk = KPP_MAP{i};  ak = ANA_MAP{i};
    kv = kpps.(sk);
    av = ana.(ak);

    mean_err_pct = 100 * abs(kv.mean - av.mean) / max(abs(av.mean), 1e-9);
    lo_err_pct   = 100 * abs(kv.ci95_lo - av.ci95_lo) / max(abs(av.ci95_lo), 1e-9);
    hi_err_pct   = 100 * abs(kv.ci95_hi - av.ci95_hi) / max(abs(av.ci95_hi), 1e-9);
    pass_i       = (mean_err_pct <= 1.0) && (lo_err_pct <= 1.0) && (hi_err_pct <= 1.0);

    fprintf('  %-12s  %10.5f  %10.5f  %10.4f  %10.4f  %10.4f  %s\n', ...
        sk, av.mean, kv.mean, mean_err_pct, lo_err_pct, hi_err_pct, tf2str(pass_i));

    if mean_err_pct > 1.0
        passed = false;
        fail_reasons{end+1} = sprintf('%s mean error %.4f%% > 1%%', sk, mean_err_pct); %#ok<AGROW>
    end
    if lo_err_pct > 1.0
        passed = false;
        fail_reasons{end+1} = sprintf('%s CI-lo error %.4f%% > 1%%', sk, lo_err_pct); %#ok<AGROW>
    end
    if hi_err_pct > 1.0
        passed = false;
        fail_reasons{end+1} = sprintf('%s CI-hi error %.4f%% > 1%%', sk, hi_err_pct); %#ok<AGROW>
    end
end

fprintf('\nVAL-SIM-005 RESULT: %s\n\n', tf2str(passed));
if ~passed
    for i = 1:numel(fail_reasons); fprintf('  - %s\n', fail_reasons{i}); end
end
result = struct('id','VAL-SIM-005','name','mcAggregation','pass',passed,'reasons',{fail_reasons});
end

% ── Helpers ──────────────────────────────────────────────────────────────────
function enc = makeEncounters(n_ped, n_veh, n_ped_hi, n_veh_hi)
    enc = struct('t',{},'shuttle_id',{},'enc_type',{},'TTC',{},'PET',{},'min_sep',{},'severity',{});
    for j = 1:n_ped
        enc(end+1).t          = j; %#ok<AGROW>
        enc(end).shuttle_id   = 1;
        enc(end).enc_type     = 'ped';
        enc(end).TTC          = 2.0;
        enc(end).PET          = 1.0;
        enc(end).min_sep      = 3.5;
        enc(end).severity     = ternary(j <= n_ped_hi, 'high', 'low');
    end
    for j = 1:n_veh
        enc(end+1).t          = n_ped + j; %#ok<AGROW>
        enc(end).shuttle_id   = 1;
        enc(end).enc_type     = 'veh';
        enc(end).TTC          = 2.0;
        enc(end).PET          = 0.0;
        enc(end).min_sep      = 9.0;
        enc(end).severity     = ternary(j <= n_veh_hi, 'high', 'low');
    end
end

function r = aggAnalytical(vals, threshold, direction)
    r.mean     = mean(vals);
    r.std      = std(vals);
    hw         = 1.960 * r.std / sqrt(numel(vals));
    r.ci95_lo  = r.mean - hw;
    r.ci95_hi  = r.mean + hw;
    r.threshold = threshold;
    if strcmp(direction,'le')
        r.pass = r.ci95_hi <= threshold;
    else
        r.pass = r.ci95_lo >= threshold;
    end
end

function s = ternary(cond, a, b)
    if cond; s = a; else; s = b; end
end

function s = tf2str(v)
    if v; s = 'PASS'; else; s = 'FAIL'; end
end
