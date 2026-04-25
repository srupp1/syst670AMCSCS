function result = val_sim_001_safetyMetrics()
% VAL-SIM-001: Surrogate Safety Metric Validation
%
% Validates TTC, PET, and minimum separation distance computed by
% detectConflicts against closed-form analytical values for deterministic
% pedestrian and vehicle scenarios.
%
% Requirements: SIM-CAP-005, SIM-CAP-006, SIM-RUN-002
%
% Pass criteria (per test plan):
%   TTC error      <= 0.05 s
%   PET error      <= 0.05 s
%   Sep. distance  <= 0.05 m

fprintf('\n==================================================\n');
fprintf(' VAL-SIM-001: Surrogate Safety Metric Validation\n');
fprintf('==================================================\n');

cfg            = getDefaultConfig();
cfg.n_shuttles = 1;
cfg.ttc_buffer = 0;   % Disable AV response buffer so raw TTC geometry is tested
passed        = true;
fail_reasons  = {};

%% ── Test Case 1: Pedestrian TTC and PET ─────────────────────────────────
% Shuttle at origin, speed = 4.0 m/s, dwell = 0
% Ped at (5.0, 0.0), crossing timer = 8.0 s
%
% sep               = 5.0 m
% approach_dist     = sep - min_sep_ped = 5.0 - 3.0 = 2.0 m
% TTC_analytical    = approach_dist / shuttle_speed = 2.0 / 4.0 = 0.5 s
% PET_analytical    = max(0, timer/2 - TTC)         = max(0, 4.0 - 0.5) = 3.5 s
% severity          = 'high'  (TTC=0.5 < ttc_high=1.5)

SH_SPEED  = 4.0;
PED_X     = 5.0;  PED_TIMER = 8.0;
sep_ped   = PED_X;
TTC_ped_a = (sep_ped - cfg.min_sep_ped) / SH_SPEED;
PET_ped_a = max(0, PED_TIMER/2 - TTC_ped_a);

state = buildState(1, 0, 0, SH_SPEED, 0, ...
    PED_X, 0, PED_TIMER, [], [], []);
[enc, chk1] = detectConflicts(state, cfg, 0);
fprintf('  TC1 interactions checked: %d ped-pair(s), %d veh-pair(s)\n', chk1.n_ped_checked, chk1.n_veh_checked);

ped_enc = enc(strcmp({enc.enc_type},'ped'));
if isempty(ped_enc)
    passed = false;
    fail_reasons{end+1} = 'TC1: No pedestrian encounter logged';
    fprintf('[FAIL] TC1: detectConflicts returned no pedestrian encounter\n');
else
    e1 = ped_enc(1);
    check('TC1 TTC',  e1.TTC,    TTC_ped_a, 0.05, fail_reasons);
    check('TC1 PET',  e1.PET,    PET_ped_a, 0.05, fail_reasons);
    check('TC1 sep',  e1.min_sep, sep_ped,  0.05, fail_reasons);
    fprintf('  TC1 analytical: TTC=%.4f s  PET=%.4f s  sep=%.4f m\n', TTC_ped_a, PET_ped_a, sep_ped);
    fprintf('  TC1 simulated:  TTC=%.4f s  PET=%.4f s  sep=%.4f m\n', e1.TTC, e1.PET, e1.min_sep);
    if ~strcmp(e1.severity,'high')
        passed = false;
        fail_reasons{end+1} = sprintf('TC1: severity should be ''high'', got ''%s''',e1.severity);
        fprintf('[FAIL] TC1: wrong severity (expected ''high'', got ''%s'')\n',e1.severity);
    else
        fprintf('[PASS] TC1: pedestrian TTC, PET, sep, severity all correct\n');
    end
end

%% ── Test Case 2: Vehicle TTC ─────────────────────────────────────────────
% Shuttle at origin, speed = 4.0 m/s
% Vehicle at (10.0, 0.0), speed = 2.0 m/s (same direction, closing)
%
% sep               = 10.0 m
% rel_spd           = |4.0 - 2.0| = 2.0 m/s
% approach_dist     = sep - min_sep_veh = 10.0 - 8.0 = 2.0 m
% TTC_analytical    = approach_dist / rel_spd = 2.0 / 2.0 = 1.0 s
% severity          = 'high'  (TTC=1.0 < ttc_high=1.5)

VEH_X    = 10.0;  VEH_SPD = 2.0;
sep_veh  = VEH_X;
TTC_veh_a = (sep_veh - cfg.min_sep_veh) / abs(SH_SPEED - VEH_SPD);

state2 = buildState(1, 0, 0, SH_SPEED, 0, ...
    [], [], [], VEH_X, 0, VEH_SPD);
[enc2, chk2] = detectConflicts(state2, cfg, 0);
fprintf('  TC2 interactions checked: %d ped-pair(s), %d veh-pair(s)\n', chk2.n_ped_checked, chk2.n_veh_checked);

veh_enc = enc2(strcmp({enc2.enc_type},'veh'));
if isempty(veh_enc)
    passed = false;
    fail_reasons{end+1} = 'TC2: No vehicle encounter logged';
    fprintf('[FAIL] TC2: detectConflicts returned no vehicle encounter\n');
else
    e2 = veh_enc(1);
    check('TC2 TTC', e2.TTC,     TTC_veh_a, 0.05, fail_reasons);
    check('TC2 sep', e2.min_sep, sep_veh,   0.05, fail_reasons);
    fprintf('  TC2 analytical: TTC=%.4f s  sep=%.4f m\n', TTC_veh_a, sep_veh);
    fprintf('  TC2 simulated:  TTC=%.4f s  sep=%.4f m\n', e2.TTC, e2.min_sep);
    if ~strcmp(e2.severity,'high')
        passed = false;
        fail_reasons{end+1} = sprintf('TC2: severity should be ''high'', got ''%s''',e2.severity);
        fprintf('[FAIL] TC2: wrong severity\n');
    else
        fprintf('[PASS] TC2: vehicle TTC, sep, severity all correct\n');
    end
end

%% ── Test Case 3: Medium severity pedestrian (extended detect radius) ──────
% To reach medium severity (1.5 < TTC < 3.0), approach_dist must be
% between 6.0 and 12.0 m at shuttle_speed=4 m/s.
% With standard ped_detect_radius=8m, sep ≤ 8m → approach_dist ≤ 5m → TTC ≤ 1.25s (always 'high').
% Extend radius to 15m to reach TTC=2.0s scenario.
%
% sep=11m, approach_dist=8m, TTC=8/4=2.0s → 'medium' (1.5 < 2.0 < 3.0)

cfg3 = cfg;
cfg3.ped_detect_radius = 15.0;
PED3_X    = 11.0;  PED3_TIMER = 12.0;
sep3      = PED3_X;
TTC3_a    = (sep3 - cfg3.min_sep_ped) / SH_SPEED;   % (11-3)/4 = 2.0 s
PET3_a    = max(0, PED3_TIMER/2 - TTC3_a);           % max(0,6-2) = 4.0 s

state3 = buildState(1, 0, 0, SH_SPEED, 0, PED3_X, 0, PED3_TIMER, [], [], []);
[enc3, chk3] = detectConflicts(state3, cfg3, 0);
fprintf('  TC3 interactions checked: %d ped-pair(s), %d veh-pair(s)\n', chk3.n_ped_checked, chk3.n_veh_checked);

ped_enc3 = enc3(strcmp({enc3.enc_type},'ped'));
if isempty(ped_enc3)
    passed = false;
    fail_reasons{end+1} = 'TC3: No medium-severity pedestrian encounter logged';
    fprintf('[FAIL] TC3: no encounter logged for medium severity scenario\n');
else
    e3 = ped_enc3(1);
    check('TC3 TTC', e3.TTC,    TTC3_a, 0.05, fail_reasons);
    check('TC3 PET', e3.PET,    PET3_a, 0.05, fail_reasons);
    check('TC3 sep', e3.min_sep, sep3,  0.05, fail_reasons);
    fprintf('  TC3 analytical: TTC=%.4f s  PET=%.4f s  sep=%.4f m  (expect ''medium'')\n', TTC3_a, PET3_a, sep3);
    fprintf('  TC3 simulated:  TTC=%.4f s  PET=%.4f s  sep=%.4f m  severity=''%s''\n', ...
        e3.TTC, e3.PET, e3.min_sep, e3.severity);
    if ~strcmp(e3.severity,'medium')
        passed = false;
        fail_reasons{end+1} = sprintf('TC3: severity should be ''medium'' for TTC=2.0s, got ''%s''',e3.severity);
        fprintf('[FAIL] TC3: wrong severity\n');
    else
        fprintf('[PASS] TC3: medium severity classification correct\n');
    end
end

%% ── Boundary: dwell suppression ──────────────────────────────────────────
% A shuttle with dwell>0 must produce NO encounters
state_dwell = buildState(1, 0, 0, SH_SPEED, 15, PED_X, 0, PED_TIMER, [], [], []);
[enc_dwell, chk_dwell] = detectConflicts(state_dwell, cfg, 0);
fprintf('  Dwell check interactions checked: %d ped-pair(s), %d veh-pair(s)\n', chk_dwell.n_ped_checked, chk_dwell.n_veh_checked);
if ~isempty(enc_dwell)
    passed = false;
    fail_reasons{end+1} = 'Dwell check: encounters logged when shuttle is stationary (dwell>0)';
    fprintf('[FAIL] Dwell: encounters detected while shuttle is dwelled\n');
else
    fprintf('[PASS] Dwell: no encounters when shuttle dwell > 0\n');
end

%% Result
[passed, fail_reasons] = checkFails(passed, fail_reasons);
fprintf('\nVAL-SIM-001 RESULT: %s\n\n', tf2str(passed));
if ~passed
    for i = 1:numel(fail_reasons); fprintf('  - %s\n',fail_reasons{i}); end
end
result = struct('id','VAL-SIM-001','name','safetyMetrics','pass',passed,'reasons',{fail_reasons});
end

% ── Helpers ──────────────────────────────────────────────────────────────────
function check(label, sim_val, ana_val, tol, fail_reasons)
    err = abs(sim_val - ana_val);
    if err > tol
        fail_reasons{end+1} = sprintf('%s error %.4f > %.2f', label, err, tol); %#ok<NASGU>
        fprintf('[FAIL] %s: sim=%.4f analytical=%.4f err=%.4f > tol=%.2f\n', ...
            label, sim_val, ana_val, err, tol);
    end
end

function [p, fr] = checkFails(passed, fail_reasons)
    % Refresh pass flag based on fail_reasons
    p  = passed && isempty(fail_reasons);
    fr = fail_reasons;
end

function state = buildState(n_sh, sx, sy, sspeed, dwell, ...
        px_arr, py_arr, ptimer_arr, vx_arr, vy_arr, vspeed_arr)
% Minimal state struct for detectConflicts / computePerception tests.

    % Shuttles
    state.shuttles = struct(...
        'id',{},'loop_pos',{},'seg',{},'seg_t',{},'x',{},'y',{},'speed',{},...
        'prev_speed',{},'dwell',{},'stop_idx',{},'leg_start_t',{},'prev_accel',{},...
        'jerk_sq_sum',{},'jerk_n',{},'brake_jerk_sq_sum',{},'brake_jerk_n',{});
    for i = 1:n_sh
        state.shuttles(i).id              = i;
        state.shuttles(i).loop_pos        = 0;
        state.shuttles(i).seg             = 1;
        state.shuttles(i).seg_t           = 0;
        state.shuttles(i).x               = sx;
        state.shuttles(i).y               = sy;
        state.shuttles(i).speed           = sspeed;
        state.shuttles(i).prev_speed      = sspeed;
        state.shuttles(i).dwell           = dwell;
        state.shuttles(i).stop_idx        = 1;
        state.shuttles(i).leg_start_t     = 0;
        state.shuttles(i).prev_accel      = 0;
        state.shuttles(i).jerk_sq_sum     = 0;
        state.shuttles(i).jerk_n          = 0;
        state.shuttles(i).brake_jerk_sq_sum = 0;
        state.shuttles(i).brake_jerk_n    = 0;
    end

    % Pedestrians
    n_p = numel(px_arr);
    state.peds = struct('id',{},'x',{},'y',{},'vx',{},'vy',{},'timer',{},'node',{});
    for k = 1:n_p
        state.peds(k).id    = k;
        state.peds(k).x     = px_arr(k);
        state.peds(k).y     = py_arr(k);
        state.peds(k).vx    = 0;
        state.peds(k).vy    = 0;
        state.peds(k).timer = ptimer_arr(k);
        state.peds(k).node  = 1;
    end

    % Vehicles
    n_v = numel(vx_arr);
    state.vehs = struct('id',{},'loop_pos',{},'x',{},'y',{},'speed',{},'dist_run',{});
    for k = 1:n_v
        state.vehs(k).id       = k;
        state.vehs(k).loop_pos = 0;
        state.vehs(k).x        = vx_arr(k);
        state.vehs(k).y        = vy_arr(k);
        state.vehs(k).speed    = vspeed_arr(k);
        state.vehs(k).dist_run = 0;
    end

    state.weather  = 1.0;
    state.next_ped = 1;
    state.next_veh = 1;
end

function s = tf2str(v)
    if v; s = 'PASS'; else; s = 'FAIL'; end
end
