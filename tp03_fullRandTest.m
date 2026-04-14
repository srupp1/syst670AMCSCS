function result = tp03_fullRandTest(varargin)
% tp03_fullRandTest  TP-03: Fully Randomized Test
%
% Verifies correct implementation of stochastic elements. Confirms that:
%   (1) The simulation produces varied outputs across replications (i.e.,
%       is not accidentally deterministic when seeds differ).
%   (2) Per-replication KPP estimates are finite with no NaN/Inf.
%   (3) Aggregated KPP statistics have valid CI bounds (lo <= mean <= hi).
%   (4) All output distributions pass basic sanity checks.
%
% Requirements: SIM-CAP-008, SIM-CAP-009, SIM-CAP-012, SIM-CAP-014
%
% Usage:
%   tp03_fullRandTest           % 30 reps (default)
%   tp03_fullRandTest('reps',10) % custom rep count
%
% Pass Criteria: Generates varied outputs with statistically valid
%                distributions; no errors; all CI bounds valid.

fprintf('\n========================================\n');
fprintf(' TP-03: Fully Randomized Test\n');
fprintf('========================================\n');

passed       = true;
fail_reasons = {};

p = inputParser;
addParameter(p, 'reps', 30, @(x) isnumeric(x) && x >= 5);
parse(p, varargin{:});
N_REPS = p.Results.reps;

cfg               = getDefaultConfig();
cfg.n_replications = N_REPS;
% Derive a fresh base seed from the current time to ensure independence
% from TP-01 / TP-02.
cfg.base_seed = mod(floor(now * 86400), 2^31 - 1);
fprintf('Config: %d reps, base_seed=%d, %d steps/rep\n\n', N_REPS, cfg.base_seed, cfg.n_steps);

try
    env = loadEnvironment('G.mat', cfg);
catch ME
    result = struct('id','TP-03','name','fullRandTest','pass',false, ...
        'reasons',{{sprintf('loadEnvironment failed: %s', ME.message)}});
    fprintf('TP-03 RESULT: FAIL\n  - %s\n\n', result.reasons{1});
    return;
end

%% Allocate storage
enc_all   = cell(N_REPS, 1);
trip_all  = cell(N_REPS, 1);
perc_all  = cell(N_REPS, 1);
jerk_all  = cell(N_REPS, 1);
enc_counts  = zeros(N_REPS, 1);
trip_counts = zeros(N_REPS, 1);
pcr_reps    = nan(N_REPS, 1);
atd_reps    = nan(N_REPS, 1);

rep = 0;
k   = 0;
try
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

        js(cfg.n_shuttles) = struct('rms_jerk',0,'rms_brake_jerk',0); %#ok<AGROW>
        for i = 1:cfg.n_shuttles
            sh = state.shuttles(i);
            if sh.jerk_n > 0
                js(i).rms_jerk = sqrt(sh.jerk_sq_sum / sh.jerk_n);
            end
            if sh.brake_jerk_n > 0
                js(i).rms_brake_jerk = sqrt(sh.brake_jerk_sq_sum / sh.brake_jerk_n);
            end
        end
        jerk_all{rep} = js;
        clear js;

        enc_counts(rep)  = numel(encounters);
        trip_counts(rep) = numel(trips);

        % Per-rep PCR estimate
        if ~isempty(encounters)
            types   = {encounters.enc_type};
            ped_enc = encounters(strcmp(types,'ped'));
            if ~isempty(ped_enc)
                sev = {ped_enc.severity};
                pcr_reps(rep) = sum(strcmp(sev,'high') | strcmp(sev,'medium')) / numel(ped_enc);
            else
                pcr_reps(rep) = 0;
            end
        else
            pcr_reps(rep) = 0;
        end

        % Per-rep ATD estimate
        if ~isempty(trips)
            atd_reps(rep) = mean([trips.delay_pct]);
        else
            atd_reps(rep) = 0;
        end

        if mod(rep, 10) == 0
            fprintf('  Completed %d / %d reps\n', rep, N_REPS);
        end
    end
    fprintf('[PASS] All %d replications completed without error\n', N_REPS);
catch ME
    passed = false;
    fail_reasons{end+1} = sprintf('Simulation error at rep %d, step %d: %s', rep, k, ME.message);
    fprintf('[FAIL] %s\n', fail_reasons{end});
    result = struct('id','TP-03','name','fullRandTest','pass',passed,'reasons',{fail_reasons});
    fprintf('\nTP-03 RESULT: FAIL\n  - %s\n\n', fail_reasons{end});
    return;
end

%% ── Check 1: Encounter counts vary (stochasticity is active) ──────────────
enc_std = std(enc_counts);
fprintf('\n--- Check 1: Stochastic variation in outputs ---\n');
fprintf('  Encounter counts:  mean=%.1f  std=%.2f  min=%d  max=%d\n', ...
    mean(enc_counts), enc_std, min(enc_counts), max(enc_counts));
fprintf('  Trip counts:       mean=%.1f  std=%.2f  min=%d  max=%d\n', ...
    mean(trip_counts), std(trip_counts), min(trip_counts), max(trip_counts));

if enc_std < 1e-6 && mean(enc_counts) > 0
    passed = false;
    fail_reasons{end+1} = ...
        'Encounter counts identical across all 30 reps — stochastic pedestrian/vehicle generation appears non-functional';
    fprintf('[FAIL] No variation in encounter counts\n');
else
    fprintf('[PASS] Encounter counts vary across reps (std=%.2f)\n', enc_std);
end

%% ── Check 2: No NaN or Inf in per-rep scalar KPP estimates ───────────────
fprintf('\n--- Check 2: Finite per-rep KPP estimates ---\n');
kpp_data = {pcr_reps, atd_reps};
kpp_names = {'PCR', 'ATD'};
for i = 1:numel(kpp_data)
    v = kpp_data{i};
    if any(isnan(v)) || any(isinf(v))
        passed = false;
        fail_reasons{end+1} = sprintf('NaN or Inf found in per-rep %s estimates', kpp_names{i});
        fprintf('[FAIL] %s: contains NaN/Inf values\n', kpp_names{i});
    else
        fprintf('[PASS] %s: all %d per-rep estimates are finite (mean=%.4f, std=%.4f)\n', ...
            kpp_names{i}, N_REPS, mean(v,'omitnan'), std(v,'omitnan'));
    end
end

%% ── Check 3: KPP aggregation produces valid CI bounds ────────────────────
fprintf('\n--- Check 3: Aggregated KPP statistics ---\n');
try
    kpps = computeKPPs(enc_all, trip_all, perc_all, jerk_all, cfg, env);
    fields  = {'PCR','IVCR','ATD','SAA_recall','UTI'};
    ci_ok   = true;
    nan_ok  = true;

    fprintf('  %-12s  %8s  [%8s, %8s]  %s\n', ...
        'KPP','Mean','CI95-lo','CI95-hi','Pass?');

    for i = 1:numel(fields)
        f = fields{i};
        kv = kpps.(f);
        fprintf('  %-12s  %8.4f  [%8.4f, %8.4f]  %s\n', ...
            f, kv.mean, kv.ci95_lo, kv.ci95_hi, tf2str(kv.pass));

        if isnan(kv.mean) || isinf(kv.mean)
            nan_ok = false;
            passed = false;
            fail_reasons{end+1} = sprintf('%s mean is NaN/Inf', f); %#ok<AGROW>
        end
        if kv.ci95_lo > kv.mean + 1e-9 || kv.mean > kv.ci95_hi + 1e-9
            ci_ok = false;
            passed = false;
            fail_reasons{end+1} = sprintf('%s CI invalid: lo=%.4f > mean=%.4f or mean > hi=%.4f', ...
                f, kv.ci95_lo, kv.mean, kv.ci95_hi); %#ok<AGROW>
        end
    end

    if nan_ok
        fprintf('[PASS] All KPP means are finite\n');
    else
        fprintf('[FAIL] One or more KPP means are NaN/Inf\n');
    end
    if ci_ok
        fprintf('[PASS] All 95%% CI bounds satisfy lo <= mean <= hi\n');
    else
        fprintf('[FAIL] One or more KPP CI bounds are invalid\n');
    end

catch ME
    passed = false;
    fail_reasons{end+1} = sprintf('computeKPPs error: %s', ME.message);
    fprintf('[FAIL] computeKPPs threw error: %s\n', ME.message);
end

%% ── Check 4: Basic distribution sanity ──────────────────────────────────
fprintf('\n--- Check 4: Distribution sanity ---\n');
% PCR in [0, 1]
if any(pcr_reps < -1e-9 | pcr_reps > 1 + 1e-9)
    passed = false;
    fail_reasons{end+1} = 'Per-rep PCR values outside [0,1]';
    fprintf('[FAIL] PCR out of range\n');
else
    fprintf('[PASS] Per-rep PCR values in [0,1]\n');
end
% ATD >= 0
if any(atd_reps < -1e-9)
    passed = false;
    fail_reasons{end+1} = 'Per-rep ATD values are negative';
    fprintf('[FAIL] ATD has negative values\n');
else
    fprintf('[PASS] Per-rep ATD values are non-negative\n');
end

%% Final result
fprintf('\nTP-03 RESULT: %s\n', tf2str(passed));
if ~passed
    for i = 1:numel(fail_reasons)
        fprintf('  - %s\n', fail_reasons{i});
    end
end
fprintf('\n');

result = struct('id','TP-03','name','fullRandTest','pass',passed,'reasons',{fail_reasons});
end

function s = tf2str(v)
    if v; s = 'PASS'; else; s = 'FAIL'; end
end
