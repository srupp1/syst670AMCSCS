function result = val_sim_002_tripPerformance()
% VAL-SIM-002: Trip Performance Metric Validation
%
% Validates correctness of trip travel time and delay calculations:
%   Part A — Formula check: verifies delay_pct = 100*(actual-baseline)/baseline
%            against known analytical inputs.
%   Part B — Simulation check: runs with speed_std=0, no agents, weather=1.0
%            and verifies that mean delay is near 0% (within time-step tolerance).
%
% Requirements: SIM-CAP-007, SIM-MET-001
%
% Pass criteria (per test plan):
%   Part A: formula error < 1e-9 (exact arithmetic)
%   Part B: |mean delay| <= 5%  (accounts for ±dt time-step quantization)

fprintf('\n===================================================\n');
fprintf(' VAL-SIM-002: Trip Performance Metric Validation\n');
fprintf('===================================================\n');

passed       = true;
fail_reasons = {};

%% ── Part A: Direct formula validation ────────────────────────────────────
fprintf('\n--- Part A: delay_pct formula check ---\n');
test_cases = [
%   actual_t  baseline_t  expected_delay_pct
    115.0,    100.0,       15.0;
    100.0,    100.0,        0.0;
     80.0,    100.0,      -20.0;
    150.0,    100.0,       50.0;
    110.0,     50.0,       20.0;
];

for i = 1:size(test_cases,1)
    actual_t   = test_cases(i,1);
    baseline_t = test_cases(i,2);
    expected   = test_cases(i,3);
    computed   = 100 * (actual_t - baseline_t) / max(baseline_t, 1);
    err        = abs(computed - expected);
    if err > 1e-9
        passed = false;
        fail_reasons{end+1} = sprintf('Formula TC%d: expected %.2f%%, got %.2f%%', i, expected, computed); %#ok<AGROW>
        fprintf('[FAIL] TC%d: actual=%.0fs baseline=%.0fs expected=%.2f%% got=%.2f%%\n', ...
            i, actual_t, baseline_t, expected, computed);
    else
        fprintf('[PASS] TC%d: delay_pct=%.2f%% (err=%.2e)\n', i, computed, err);
    end
end

%% ── Part B: Zero-delay scenario ──────────────────────────────────────────
fprintf('\n--- Part B: deterministic simulation (speed_std=0, no agents) ---\n');

cfg                 = getDefaultConfig();
cfg.n_replications  = 3;
cfg.n_shuttles      = 1;
cfg.speed_std       = 0;       % Exact speed, no variation
cfg.weather_mean    = 1.0;
cfg.weather_std     = 0;       % Fixed fair weather
cfg.ped_rate_base   = 0;       % No pedestrians
cfg.veh_rate        = 0;       % No background vehicles
cfg.base_seed       = 42;

try
    env = loadEnvironment('G.mat', cfg);
catch ME
    result = struct('id','VAL-SIM-002','name','tripPerformance','pass',false, ...
        'reasons',{{sprintf('loadEnvironment failed: %s', ME.message)}});
    fprintf('VAL-SIM-002 RESULT: FAIL\n  - %s\n\n', result.reasons{1});
    return;
end

% Analytical: with speed=speed_mean*1.0=4.0 m/s and fixed baseline
% (baseline_leg_t = leg_dist/speed + dwell_time), delay_pct ≈ 0%.
% Residual error comes only from discrete time-step stop detection (±dt).
% Max time-step error = dt / min(baseline_leg_t) * 100%
min_baseline_t = min(env.baseline_leg_t);
max_expected_err_pct = cfg.dt / min_baseline_t * 100;
fprintf('  Minimum leg baseline time: %.1f s\n', min_baseline_t);
fprintf('  Max expected quantization error: ±%.1f%%  (dt=%.0fs / min_leg_t)\n', ...
    max_expected_err_pct, cfg.dt);

all_trips = struct('shuttle_id',{},'leg',{},'start_node',{},'end_node',{}, ...
    'actual_t',{},'baseline_t',{},'delay_pct',{},'t',{});

for rep = 1:cfg.n_replications
    rng(cfg.base_seed + rep - 1);
    state = initReplication(env, cfg);
    enc_dummy = struct('t',{},'shuttle_id',{},'enc_type',{}, ...
                       'TTC',{},'PET',{},'min_sep',{},'severity',{});
    perc_dummy = struct('t',{},'shuttle_id',{},'agent_type',{}, ...
                        'true_x',{},'true_y',{},'det_x',{},'det_y',{}, ...
                        'detected',{},'pred_err',{},'latency',{});

    for k = 1:cfg.n_steps
        t_sim = cfg.t_start + (k-1)*cfg.dt;
        [state, enc_k, trip_k, ~] = stepSimulation(state, env, cfg, t_sim);
        if ~isempty(enc_k);  enc_dummy  = [enc_dummy,  enc_k];  end %#ok<AGROW>
        if ~isempty(trip_k); all_trips  = [all_trips, trip_k];  end %#ok<AGROW>
    end
    fprintf('  Rep %d: %d trips completed\n', rep, numel(all_trips));
end

if isempty(all_trips)
    passed = false;
    fail_reasons{end+1} = 'Part B: no trips recorded in 3 replications';
    fprintf('[FAIL] Part B: no trips recorded\n');
else
    delay_pcts = [all_trips.delay_pct];
    mean_delay = mean(delay_pcts);
    std_delay  = std(delay_pcts);
    max_delay  = max(abs(delay_pcts));

    fprintf('\n  Trips recorded: %d\n', numel(delay_pcts));
    fprintf('  Delay %%:  mean=%.3f%%  std=%.3f%%  max_abs=%.3f%%\n', ...
        mean_delay, std_delay, max_delay);
    fprintf('  Tolerance: |mean| <= %.1f%%  (quantization bound)\n', max_expected_err_pct);

    % Check that mean delay is within the quantization tolerance
    TOLERANCE_PCT = max(5.0, max_expected_err_pct);
    if abs(mean_delay) > TOLERANCE_PCT
        passed = false;
        fail_reasons{end+1} = sprintf('Part B: mean delay %.3f%% exceeds tolerance ±%.1f%%', ...
            mean_delay, TOLERANCE_PCT);
        fprintf('[FAIL] Part B: mean delay too large\n');
    else
        fprintf('[PASS] Part B: mean delay within tolerance\n');
    end

    % Verify actual_t and baseline_t fields are positive
    if any([all_trips.actual_t] <= 0) || any([all_trips.baseline_t] <= 0)
        passed = false;
        fail_reasons{end+1} = 'Part B: actual_t or baseline_t is non-positive';
        fprintf('[FAIL] Part B: non-positive travel times recorded\n');
    else
        fprintf('[PASS] Part B: all trip times are positive\n');
    end

    % Cross-check formula: recompute delay_pct and compare
    formula_errs = abs([all_trips.delay_pct] - ...
        100 * ([all_trips.actual_t] - [all_trips.baseline_t]) ./ ...
        max([all_trips.baseline_t], 1));
    if max(formula_errs) > 1e-6
        passed = false;
        fail_reasons{end+1} = sprintf('Part B: delay_pct formula error max=%.2e', max(formula_errs));
        fprintf('[FAIL] Part B: formula cross-check failed (max err=%.2e)\n', max(formula_errs));
    else
        fprintf('[PASS] Part B: delay_pct formula cross-check passed (max err=%.2e)\n', max(formula_errs));
    end
end

fprintf('\nVAL-SIM-002 RESULT: %s\n\n', tf2str(passed));
if ~passed
    for i = 1:numel(fail_reasons); fprintf('  - %s\n', fail_reasons{i}); end
end
result = struct('id','VAL-SIM-002','name','tripPerformance','pass',passed,'reasons',{fail_reasons});
end

function s = tf2str(v)
    if v; s = 'PASS'; else; s = 'FAIL'; end
end
