function result = tp02_seededRandTest()
% tp02_seededRandTest  TP-02: Seeded Randomness Test
%
% Verifies deterministic reproducibility: running the simulation twice
% with identical configuration and identical base_seed produces identical
% output datasets in every replication.
%
% Requirements: SIM-CAP-011, SIM-CS-004, SIM-CS-009
%
% Replications: 5 (two full runs of 5 reps each)
% Pass Criteria: All per-replication output counts and numerical values
%                are bit-for-bit identical between Run A and Run B.

fprintf('\n========================================\n');
fprintf(' TP-02: Seeded Randomness Test\n');
fprintf('========================================\n');

passed       = true;
fail_reasons = {};
N_REPS       = 5;
SEED         = 42;

cfg               = getDefaultConfig();
cfg.n_replications = N_REPS;
cfg.base_seed     = SEED;

try
    env = loadEnvironment('G.mat', cfg);
    fprintf('Config: %d reps, base_seed=%d, %d steps/rep\n\n', N_REPS, SEED, cfg.n_steps);
catch ME
    result = struct('id','TP-02','name','seededRandTest','pass',false, ...
        'reasons',{{sprintf('loadEnvironment failed: %s', ME.message)}});
    fprintf('TP-02 RESULT: FAIL\n  - %s\n\n', result.reasons{1});
    return;
end

%% Run A
fprintf('--- Run A (seed=%d) ---\n', SEED);
[A, err] = runReps(cfg, env, N_REPS, SEED);
if ~isempty(err)
    result = struct('id','TP-02','name','seededRandTest','pass',false,'reasons',{{err}});
    fprintf('TP-02 RESULT: FAIL\n  - %s\n\n', err);
    return;
end

%% Run B (same seed)
fprintf('--- Run B (seed=%d) ---\n', SEED);
[B, err] = runReps(cfg, env, N_REPS, SEED);
if ~isempty(err)
    result = struct('id','TP-02','name','seededRandTest','pass',false,'reasons',{{err}});
    fprintf('TP-02 RESULT: FAIL\n  - %s\n\n', err);
    return;
end

%% Compare outputs
fprintf('\n--- Comparing Run A vs Run B ---\n');
fprintf('%-6s  %-12s  %-12s  %-12s  %-14s  %-14s  %s\n', ...
    'Rep', 'Enc (A|B)', 'Trip (A|B)', 'Perc (A|B)', 'MaxTTC_err', 'MaxDelay_err', 'Match?');

for rep = 1:N_REPS
    enc_nA  = numel(A.enc{rep});
    enc_nB  = numel(B.enc{rep});
    trip_nA = numel(A.trip{rep});
    trip_nB = numel(B.trip{rep});
    perc_nA = numel(A.perc{rep});
    perc_nB = numel(B.perc{rep});

    cnt_match = (enc_nA == enc_nB) && (trip_nA == trip_nB) && (perc_nA == perc_nB);

    % Deep numerical comparison for encounters
    max_ttc_err = 0;
    if enc_nA == enc_nB && enc_nA > 0
        ttcA = [A.enc{rep}.TTC];
        ttcB = [B.enc{rep}.TTC];
        max_ttc_err = max(abs(ttcA - ttcB));
    end

    % Deep numerical comparison for trips
    max_dly_err = 0;
    if trip_nA == trip_nB && trip_nA > 0
        dlyA = [A.trip{rep}.delay_pct];
        dlyB = [B.trip{rep}.delay_pct];
        max_dly_err = max(abs(dlyA - dlyB));
    end

    rep_pass = cnt_match && (max_ttc_err < 1e-10) && (max_dly_err < 1e-10);

    fprintf('%3d     %4d | %-4d   %4d | %-4d   %4d | %-4d   %12.2e    %12.2e    %s\n', ...
        rep, enc_nA, enc_nB, trip_nA, trip_nB, perc_nA, perc_nB, ...
        max_ttc_err, max_dly_err, tf2str(rep_pass));

    if ~rep_pass
        passed = false;
        if ~cnt_match
            fail_reasons{end+1} = sprintf( ...
                'Rep %d: output counts differ — enc(%d vs %d) trip(%d vs %d) perc(%d vs %d)', ...
                rep, enc_nA, enc_nB, trip_nA, trip_nB, perc_nA, perc_nB); %#ok<AGROW>
        end
        if max_ttc_err >= 1e-10
            fail_reasons{end+1} = sprintf( ...
                'Rep %d: TTC values differ (max err = %.2e)', rep, max_ttc_err); %#ok<AGROW>
        end
        if max_dly_err >= 1e-10
            fail_reasons{end+1} = sprintf( ...
                'Rep %d: delay_pct values differ (max err = %.2e)', rep, max_dly_err); %#ok<AGROW>
        end
    end
end

fprintf('\nTP-02 RESULT: %s\n', tf2str(passed));
if ~passed
    for i = 1:numel(fail_reasons)
        fprintf('  - %s\n', fail_reasons{i});
    end
end
fprintf('\n');

result = struct('id','TP-02','name','seededRandTest','pass',passed,'reasons',{fail_reasons});
end

% ── Subfunction ──────────────────────────────────────────────────────────────
function [res, err] = runReps(cfg, env, n_reps, base_seed)
err = '';
res.enc  = cell(n_reps, 1);
res.trip = cell(n_reps, 1);
res.perc = cell(n_reps, 1);
rep = 0;
k   = 0;
try
    for rep = 1:n_reps
        rng(base_seed + rep - 1);
        state = initReplication(env, cfg);

        encounters = struct('t',{},'shuttle_id',{},'enc_type',{},'agent_id',{}, ...
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

        res.enc{rep}  = encounters;
        res.trip{rep} = trips;
        res.perc{rep} = perception;
        fprintf('  rep %d: %d enc, %d trips, %d perc\n', ...
            rep, numel(encounters), numel(trips), numel(perception));
    end
catch ME
    err = sprintf('Simulation error at rep %d, step %d: %s', rep, k, ME.message);
end
end

function s = tf2str(v)
    if v; s = 'PASS'; else; s = 'FAIL'; end
end
