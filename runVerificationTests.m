function runVerificationTests(varargin)
% runVerificationTests  Run all automated V&V tests for the ACMSCS simulation.
%
% Test sections:
%   Simulation Verification  (TP-01 to TP-03) — structural/stochastic checks
%   Simulation Validation    (VAL-SIM-001 to 005) — formula/model accuracy
%   Objective System Verif.  (OSV-PCR/IVCR/ATD/SAA/UTI) — KPP requirements
%
% Note: TP-04 (Implementation Inspection) is manual and excluded.
%
% Usage:
%   runVerificationTests           % all 13 tests  (full reps, ~30-45 min)
%   runVerificationTests('fast')   % reduced reps, quicker (~10 min)

clc;
fprintf('=======================================================\n');
fprintf('  ACMSCS V&V Test Suite\n');
fprintf('  KSTM Labs  |  %s\n', datestr(now,'yyyy-mm-dd HH:MM'));
fprintf('=======================================================\n\n');

FAST_MODE = (nargin > 0 && strcmpi(varargin{1},'fast'));
if FAST_MODE
    fprintf('FAST MODE: reduced replications for TP-03 and OSV tests\n\n');
end

TP03_REPS = 30;  OSV_REPS = 100;
if FAST_MODE
    TP03_REPS = 10;  OSV_REPS = 30;
end

tic;
all_results = {};

%% ── Section 1: Simulation Verification ──────────────────────────────────
fprintf('\n══════════════════════════════════════\n');
fprintf('  SECTION 1: Simulation Verification\n');
fprintf('══════════════════════════════════════\n');

all_results{end+1} = tp01_smokeTest();
all_results{end+1} = tp02_seededRandTest();
all_results{end+1} = tp03_fullRandTest('reps', TP03_REPS);

%% ── Section 2: Simulation Validation ────────────────────────────────────
fprintf('\n══════════════════════════════════════\n');
fprintf('  SECTION 2: Simulation Validation\n');
fprintf('══════════════════════════════════════\n');

all_results{end+1} = val_sim_001_safetyMetrics();
all_results{end+1} = val_sim_002_tripPerformance();
all_results{end+1} = val_sim_003_perceptionMetrics();
all_results{end+1} = val_sim_004_motionDynamics();
all_results{end+1} = val_sim_005_mcAggregation();

%% ── Section 3: Objective System Verification ─────────────────────────────
fprintf('\n══════════════════════════════════════════════\n');
fprintf('  SECTION 3: Objective System Verification\n');
fprintf('══════════════════════════════════════════════\n');

osv = osv_all('reps', OSV_REPS);
all_results{end+1} = osv.pcr;
all_results{end+1} = osv.ivcr;
all_results{end+1} = osv.atd;
all_results{end+1} = osv.saa;
all_results{end+1} = osv.uti;

%% ── Final Summary ────────────────────────────────────────────────────────
elapsed  = toc;
n_tests  = numel(all_results);
n_pass   = sum(cellfun(@(r) r.pass, all_results));
n_fail   = n_tests - n_pass;

fprintf('\n=======================================================\n');
fprintf('  V&V TEST SUITE SUMMARY\n');
fprintf('=======================================================\n');
fprintf('%-16s  %-28s  %s\n', 'Test ID', 'Name', 'Result');
fprintf('%-16s  %-28s  %s\n', '-------', '----', '------');

sections = {'Simulation Verification','','', ...
            'Simulation Validation','','','','', ...
            'Obj. System Verif.','','','',''};
for i = 1:n_tests
    r   = all_results{i};
    tag = 'PASS';
    if ~r.pass; tag = 'FAIL'; end
    fprintf('%-16s  %-28s  %s\n', r.id, r.name, tag);
    if ~r.pass && ~isempty(r.reasons)
        for j = 1:numel(r.reasons)
            fprintf('  %-14s  -> %s\n', '', r.reasons{j});
        end
    end
end

fprintf('\n%d / %d tests PASSED  |  %d FAILED  |  %.1f s total\n\n', ...
    n_pass, n_tests, n_fail, elapsed);

if n_fail == 0
    fprintf('OVERALL: ALL %d AUTOMATED V&V TESTS PASSED\n\n', n_tests);
else
    fprintf('OVERALL: %d TEST(S) FAILED — see details above\n\n', n_fail);
end

fprintf('Note: TP-04 (Implementation Inspection) requires manual review.\n\n');
end
