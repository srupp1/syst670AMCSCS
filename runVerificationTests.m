% runVerificationTests.m
% Run all automated simulation verification tests (TP-01 through TP-03).
%
% TP-04 (Implementation Inspection) is a manual test and is not included.
%
% Usage:
%   runVerificationTests          % run from Syst670 folder
%
% Output:
%   Summary table printed to console.
%   Each test function also prints detailed pass/fail diagnostics.

clc;
fprintf('=====================================================\n');
fprintf('  ACMSCS Simulation Verification Tests\n');
fprintf('  KSTM Labs  |  %s\n', datestr(now, 'yyyy-mm-dd HH:MM'));
fprintf('=====================================================\n');

tic;

r1 = tp01_smokeTest();
r2 = tp02_seededRandTest();
r3 = tp03_fullRandTest();

elapsed = toc;

%% Summary
fprintf('=====================================================\n');
fprintf('  VERIFICATION TEST SUMMARY\n');
fprintf('=====================================================\n');
fprintf('%-8s  %-22s  %s\n', 'Test ID', 'Name', 'Result');
fprintf('%-8s  %-22s  %s\n', '-------', '----', '------');

results = {r1, r2, r3};
n_pass = 0;
for i = 1:numel(results)
    r = results{i};
    res_str = 'PASS';
    if ~r.pass; res_str = 'FAIL'; end
    fprintf('%-8s  %-22s  %s\n', r.id, r.name, res_str);
    if r.pass; n_pass = n_pass + 1; end
    if ~r.pass && ~isempty(r.reasons)
        for j = 1:numel(r.reasons)
            fprintf('          -> %s\n', r.reasons{j});
        end
    end
end

fprintf('\n%d / %d tests passed   (total elapsed: %.1f s)\n\n', ...
    n_pass, numel(results), elapsed);

if n_pass == numel(results)
    fprintf('OVERALL: ALL AUTOMATED VERIFICATION TESTS PASSED\n\n');
else
    fprintf('OVERALL: %d TEST(S) FAILED — see details above\n\n', ...
        numel(results) - n_pass);
end

fprintf('Note: TP-04 (Implementation Inspection) requires manual review.\n\n');
