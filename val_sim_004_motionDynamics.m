function result = val_sim_004_motionDynamics()
% VAL-SIM-004: Motion Dynamics Metric Validation
%
% Validates that jerk values computed by updateShuttles match the
% analytical formula for a controlled speed sequence.
%
% The code implements:
%   accel_k = (new_speed_k - prev_speed_k) / dt
%   jerk_k  = (accel_k - prev_accel_{k-1}) / dt
%   rms_jerk = sqrt(mean(jerk_k^2))
%
% where prev_speed_k is s.speed from the *beginning* of the previous step
% (i.e., one sample behind new_speed).  This analytical mirror is used to
% compute expected values — the test validates the implementation, not the
% physical accuracy of the formula.
%
% Requirements: SIM-CAP-004, SIM-CAP-007
%
% Pass criteria (per test plan):
%   RMS jerk error          <= 0.05 m/s³
%   RMS braking jerk error  <= 0.05 m/s³
%   jerk_n count correct

fprintf('\n====================================================\n');
fprintf(' VAL-SIM-004: Motion Dynamics Metric Validation\n');
fprintf('====================================================\n');

passed       = true;
fail_reasons = {};

%% Build environment and initial state
cfg              = getDefaultConfig();
cfg.n_shuttles   = 1;
cfg.speed_std    = 0;       % Forces normrnd(mean,0) = mean exactly
cfg.weather_mean = 1.0;
cfg.weather_std  = 0;
cfg.ped_rate_base = 0;
cfg.veh_rate     = 0;
cfg.dwell_time   = 0;   % No dwell so jerk is accumulated every step, matching analytical model
cfg.base_seed    = 42;

try
    env = loadEnvironment('G.mat', cfg);
catch ME
    result = struct('id','VAL-SIM-004','name','motionDynamics','pass',false, ...
        'reasons',{{sprintf('loadEnvironment failed: %s', ME.message)}});
    fprintf('VAL-SIM-004 RESULT: FAIL\n  - %s\n\n', result.reasons{1});
    return;
end

%% Define controlled speed sequence
% Covers: acceleration, constant speed, deceleration, re-acceleration
% Each value is the cfg.speed_mean for that step (speed_std=0 → exact).
% All within [1.0, 6.0] m/s clamp range.
speed_seq = [4.0, 4.5, 5.0, 5.0, 4.5, 4.0, 3.5, 4.0, 4.5, 4.0];
N_STEPS   = numel(speed_seq);
DT        = cfg.dt;   % 10 s

%% Analytical computation (mirrors updateShuttles formula exactly)
% Track s.speed and s.prev_speed separately to match the code's bookkeeping.
v0         = 4.0;   % initial speed (set in initReplication with speed_std=0)
s_speed    = v0;
s_prev_sp  = v0;    % initReplication: prev_speed = speed
s_prev_ac  = 0;     % initReplication: prev_accel = 0

ana_jerks       = zeros(1, N_STEPS);
ana_accel       = zeros(1, N_STEPS);
ana_jerk_sq     = 0;
ana_brake_jerk_sq = 0;
n_jerk   = 0;
n_brake  = 0;

for k = 1:N_STEPS
    v_new = speed_seq(k) * 1.0;   % weather=1, std=0
    v_new = max(1.0, min(6.0, v_new));

    a_k = (v_new - s_prev_sp) / DT;     % uses prev_speed (one step behind)
    j_k = (a_k   - s_prev_ac) / DT;

    ana_accel(k)  = a_k;
    ana_jerks(k)  = j_k;
    ana_jerk_sq   = ana_jerk_sq + j_k^2;
    n_jerk        = n_jerk + 1;

    if a_k < 0
        ana_brake_jerk_sq = ana_brake_jerk_sq + j_k^2;
        n_brake = n_brake + 1;
    end

    s_prev_ac = a_k;
    s_prev_sp = s_speed;   % save *current* speed (before applying v_new)
    s_speed   = v_new;
end

ana_rms_jerk  = sqrt(ana_jerk_sq / n_jerk);
if n_brake > 0
    ana_rms_brake = sqrt(ana_brake_jerk_sq / n_brake);
else
    ana_rms_brake = 0;
end

fprintf('Speed sequence: [%s] m/s\n', num2str(speed_seq,'%.1f '));
fprintf('DT = %.0f s\n\n', DT);
fprintf('Analytical accelerations (m/s²): [%s]\n', num2str(ana_accel,'%+.4f '));
fprintf('Analytical jerks       (m/s³): [%s]\n', num2str(ana_jerks,'%+.4f '));
fprintf('Analytical RMS jerk:        %.6f m/s³\n', ana_rms_jerk);
fprintf('Analytical RMS braking jerk: %.6f m/s³  (%d braking steps)\n', ana_rms_brake, n_brake);

%% Run simulation for N_STEPS steps with controlled speed sequence
rng(cfg.base_seed);
state = initReplication(env, cfg);
% Override shuttle initial speed to v0 (should already be v0 since speed_std=0)
state.shuttles(1).speed      = v0;
state.shuttles(1).prev_speed = v0;
state.shuttles(1).prev_accel = 0;

for k = 1:N_STEPS
    cfg.speed_mean = speed_seq(k);   % Force exact speed for this step
    t_sim = cfg.t_start + (k-1) * cfg.dt;
    [state, ~] = updateShuttles(state, env, cfg, t_sim);
end

sh = state.shuttles(1);
sim_jerk_n     = sh.jerk_n;
sim_brake_n    = sh.brake_jerk_n;
sim_rms_jerk   = 0;
sim_rms_brake  = 0;
if sh.jerk_n > 0
    sim_rms_jerk  = sqrt(sh.jerk_sq_sum  / sh.jerk_n);
end
if sh.brake_jerk_n > 0
    sim_rms_brake = sqrt(sh.brake_jerk_sq_sum / sh.brake_jerk_n);
end

%% Compare
fprintf('\n--- Results ---\n');
fprintf('  %-28s  %12s  %12s  %10s\n', 'Metric', 'Simulated', 'Analytical', 'Error');
fprintf('  %-28s  %12s  %12s  %10s\n', '------', '---------', '----------', '-----');
fprintf('  %-28s  %12.6f  %12.6f  %10.6f\n', 'RMS jerk (m/s³)', ...
    sim_rms_jerk, ana_rms_jerk, abs(sim_rms_jerk - ana_rms_jerk));
fprintf('  %-28s  %12.6f  %12.6f  %10.6f\n', 'RMS braking jerk (m/s³)', ...
    sim_rms_brake, ana_rms_brake, abs(sim_rms_brake - ana_rms_brake));
fprintf('  %-28s  %12d  %12d  %10d\n', 'jerk_n count', sim_jerk_n, n_jerk, abs(sim_jerk_n-n_jerk));
fprintf('  %-28s  %12d  %12d  %10d\n', 'brake_jerk_n count', sim_brake_n, n_brake, abs(sim_brake_n-n_brake));

TOL = 0.05;   % m/s³ per test plan

err_rms  = abs(sim_rms_jerk  - ana_rms_jerk);
err_brk  = abs(sim_rms_brake - ana_rms_brake);

if err_rms > TOL
    passed = false;
    fail_reasons{end+1} = sprintf('RMS jerk error %.6f > %.2f m/s³', err_rms, TOL);
    fprintf('[FAIL] RMS jerk error too large\n');
else
    fprintf('[PASS] RMS jerk within tolerance (err=%.6f <= %.2f m/s³)\n', err_rms, TOL);
end

if err_brk > TOL
    passed = false;
    fail_reasons{end+1} = sprintf('RMS braking jerk error %.6f > %.2f m/s³', err_brk, TOL);
    fprintf('[FAIL] RMS braking jerk error too large\n');
else
    fprintf('[PASS] RMS braking jerk within tolerance (err=%.6f <= %.2f m/s³)\n', err_brk, TOL);
end

if sim_jerk_n ~= n_jerk
    passed = false;
    fail_reasons{end+1} = sprintf('jerk_n mismatch: sim=%d analytical=%d', sim_jerk_n, n_jerk);
    fprintf('[FAIL] jerk_n count mismatch\n');
else
    fprintf('[PASS] jerk_n count correct (%d)\n', sim_jerk_n);
end

if sim_brake_n ~= n_brake
    passed = false;
    fail_reasons{end+1} = sprintf('brake_jerk_n mismatch: sim=%d analytical=%d', sim_brake_n, n_brake);
    fprintf('[FAIL] brake_jerk_n count mismatch\n');
else
    fprintf('[PASS] brake_jerk_n count correct (%d)\n', sim_brake_n);
end

fprintf('\nVAL-SIM-004 RESULT: %s\n\n', tf2str(passed));
if ~passed
    for i = 1:numel(fail_reasons); fprintf('  - %s\n', fail_reasons{i}); end
end
result = struct('id','VAL-SIM-004','name','motionDynamics','pass',passed,'reasons',{fail_reasons});
end

function s = tf2str(v)
    if v; s = 'PASS'; else; s = 'FAIL'; end
end
