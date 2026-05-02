function result = tp01_smokeTest()
% tp01_smokeTest  TP-01: Smoke Test
%
% Verifies that the simulation can execute a basic scenario:
% initialization, execution, output generation, and termination all work
% correctly without errors.
%
% Requirements: SIM-CAP-002, SIM-CAP-005, SIM-CAP-006, SIM-CAP-007,
%               SIM-EIF-001, SIM-EIF-002, SIM-IIF-001, SIM-CS-002,
%               SIM-CS-003, SIM-CS-005
%
% Replications: 3
% Pass Criteria: Simulation executes without errors and produces all
%                required output datasets (enc_all, trip_all, perc_all,
%                jerk_all) with correct field structure, and computeKPPs
%                returns all five KPP structs.

fprintf('\n========================================\n');
fprintf(' TP-01: Smoke Test\n');
fprintf('========================================\n');

passed      = true;
fail_reasons = {};
N_REPS      = 10;

%% Setup
cfg             = getDefaultConfig();
cfg.n_replications = N_REPS;
cfg.base_seed   = 42;

fprintf('Config: %d reps, %d steps/rep, dt=%.0f s\n', ...
    N_REPS, cfg.n_steps, cfg.dt);

try
    env = loadEnvironment('G.mat', cfg);
    fprintf('[PASS] loadEnvironment: %d nodes, %d edges, loop=%.0f m\n', ...
        env.n_nodes, env.n_edges, env.loop_length);
catch ME
    result = makeResult('TP-01','smokeTest',false, ...
        {sprintf('loadEnvironment failed: %s', ME.message)});
    printResult(result);
    return;
end

%% Run simulation loop
enc_all  = cell(N_REPS, 1);
trip_all = cell(N_REPS, 1);
perc_all = cell(N_REPS, 1);
jerk_all = cell(N_REPS, 1);
rep      = 0;

try
    for rep = 1:N_REPS
        rng(cfg.base_seed + rep - 1);
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

        enc_all{rep}  = encounters;
        trip_all{rep} = trips;
        perc_all{rep} = perception;

        js = repmat(struct('rms_jerk',0,'rms_brake_jerk',0,'jerk_n',0,'brake_jerk_n',0), 1, cfg.n_shuttles);
        for i = 1:cfg.n_shuttles
            sh = state.shuttles(i);
            js(i).jerk_n       = sh.jerk_n;
            js(i).brake_jerk_n = sh.brake_jerk_n;
            if sh.jerk_n > 0
                js(i).rms_jerk = sqrt(sh.jerk_sq_sum / sh.jerk_n);
            end
            if sh.brake_jerk_n > 0
                js(i).rms_brake_jerk = sqrt(sh.brake_jerk_sq_sum / sh.brake_jerk_n);
            end
        end
        jerk_all{rep} = js;
        clear js;

        fprintf('  Rep %d: %3d encounters, %3d trips, %3d perception events\n', ...
            rep, numel(encounters), numel(trips), numel(perception));
    end
    fprintf('[PASS] All %d replications completed without error\n', N_REPS);
catch ME
    passed = false;
    fail_reasons{end+1} = sprintf('Simulation error at rep %d, step %d: %s', rep, k, ME.message);
    fprintf('[FAIL] %s\n', fail_reasons{end});
    result = makeResult('TP-01','smokeTest',false,fail_reasons);
    printResult(result);
    return;
end

%% Check output dataset structure
req_enc_fields  = {'t','shuttle_id','enc_type','TTC','PET','min_sep','severity'};
req_trip_fields = {'shuttle_id','leg','start_node','end_node','actual_t','baseline_t','delay_pct','t'};
req_perc_fields = {'t','shuttle_id','agent_type','true_x','true_y','det_x','det_y','detected','pred_err','latency'};
req_jerk_fields = {'rms_jerk','rms_brake_jerk'};

struct_ok = true;
for rep = 1:N_REPS
    struct_ok = struct_ok & checkFields(enc_all{rep},  req_enc_fields,  sprintf('enc_all{%d}',rep),  fail_reasons);
    struct_ok = struct_ok & checkFields(trip_all{rep}, req_trip_fields, sprintf('trip_all{%d}',rep), fail_reasons);
    struct_ok = struct_ok & checkFields(perc_all{rep}, req_perc_fields, sprintf('perc_all{%d}',rep), fail_reasons);
    struct_ok = struct_ok & checkFields(jerk_all{rep}, req_jerk_fields, sprintf('jerk_all{%d}',rep), fail_reasons);
end
if ~struct_ok
    passed = false;
    fprintf('[FAIL] One or more output datasets have incorrect field structure\n');
else
    fprintf('[PASS] All output datasets have correct field structure\n');
end

%% Check computeKPPs
try
    kpps = computeKPPs(enc_all, trip_all, perc_all, jerk_all, cfg, env);
    req_kpp  = {'PCR','IVCR','ATD','SAA_recall','UTI'};
    req_sub  = {'mean','ci95_lo','ci95_hi','pass'};
    kpp_ok   = true;
    for i = 1:numel(req_kpp)
        f = req_kpp{i};
        if ~isfield(kpps, f)
            kpp_ok = false;
            fail_reasons{end+1} = sprintf('KPP field ''%s'' missing from computeKPPs output', f);
        else
            for j = 1:numel(req_sub)
                if ~isfield(kpps.(f), req_sub{j})
                    kpp_ok = false;
                    fail_reasons{end+1} = sprintf('kpps.%s.%s missing', f, req_sub{j});
                end
            end
        end
    end
    if kpp_ok
        fprintf('[PASS] computeKPPs returned all 5 KPP structs with required sub-fields\n');
        fprintf('\n  KPP Results (%d reps):\n', N_REPS);
        fprintf('  %-12s  %8s  [%8s, %8s]  %s\n','KPP','Mean','CI95-lo','CI95-hi','Pass?');
        for i = 1:numel(req_kpp)
            f = req_kpp{i};
            k = kpps.(f);
            fprintf('  %-12s  %8.4f  [%8.4f, %8.4f]  %s\n', ...
                f, k.mean, k.ci95_lo, k.ci95_hi, tf2str(k.pass));
        end
    else
        passed = false;
        fprintf('[FAIL] computeKPPs output structure invalid\n');
    end
catch ME
    passed = false;
    fail_reasons{end+1} = sprintf('computeKPPs error: %s', ME.message);
    fprintf('[FAIL] computeKPPs threw error: %s\n', ME.message);
end

result = makeResult('TP-01','smokeTest',passed,fail_reasons);
printResult(result);
end

% ── Helpers ──────────────────────────────────────────────────────────────────
function ok = checkFields(s, req_fields, label, fail_reasons) %#ok<INUSL>
    ok = true;
    if ~isstruct(s)
        ok = false;
        fail_reasons{end+1} = sprintf('%s is not a struct', label); %#ok<NASGU>
        return;
    end
    % Empty struct arrays still have fields — check fieldnames
    if ~isempty(s)
        for i = 1:numel(req_fields)
            if ~isfield(s, req_fields{i})
                ok = false;
                fail_reasons{end+1} = sprintf('%s missing field ''%s''', label, req_fields{i}); %#ok<NASGU>
            end
        end
    end
end

function r = makeResult(id, name, pass, reasons)
    r = struct('id',id,'name',name,'pass',pass,'reasons',{reasons});
end

function printResult(r)
    fprintf('\nTP-01 RESULT: %s\n', tf2str(r.pass));
    if ~r.pass
        for i = 1:numel(r.reasons)
            fprintf('  - %s\n', r.reasons{i});
        end
    end
    fprintf('\n');
end

function s = tf2str(v)
    if v; s = 'PASS'; else; s = 'FAIL'; end
end
