function exportVVReport(varargin)
% exportVVReport  Generate a V&V documentation report (self-contained HTML).
%
% Runs all 13 automated V&V tests and produces an HTML file that satisfies
% the V&V document requirements for each test:
%   (1) Captured simulation data
%   (2) Results of analysis of simulation outputs
%   (3) Determination of whether the test passed or failed
%   (4) Rationale / justification if the test failed
%
% Usage:
%   exportVVReport              % full run → VV_Report_<timestamp>.html
%   exportVVReport('fast')      % reduced reps for quick preview
%   exportVVReport('file','my_report.html')
%   exportVVReport('fast','file','preview.html')

%% ── Parse arguments ──────────────────────────────────────────────────────
FAST      = any(strcmpi(varargin, 'fast'));
file_idx  = find(strcmpi(varargin, 'file'));
if ~isempty(file_idx) && file_idx < numel(varargin)
    out_file = varargin{file_idx + 1};
else
    out_file = ['VV_Report_', datestr(now,'yyyymmdd_HHMMSS'), '.html'];
end

TP03_REPS = 30;  OSV_REPS = 100;
if FAST,  TP03_REPS = 10;  OSV_REPS = 30;  end

fprintf('\n=======================================================\n');
fprintf('  ACMSCS V&V Report Generator\n');
fprintf('  Mode: %s  |  Output: %s\n', ...
    ternary(FAST,'FAST','FULL'), out_file);
fprintf('=======================================================\n\n');

%% ── Test metadata ─────────────────────────────────────────────────────────
% Columns: {ShortID, DisplayName, Section, Requirements, Objective, DataNote}
TESTS = {
'VER-SIM-01', 'Smoke Test', 'Simulation Verification', ...
    'SIM-CAP-002, SIM-CAP-005, SIM-CAP-006, SIM-CAP-007, SIM-EIF-001, SIM-EIF-002, SIM-IIF-001, SIM-CS-002, SIM-CS-003, SIM-CS-005', ...
    ['Verifies that the simulation initialises, executes for all time steps, and ' ...
     'terminates without error. Confirms all required output datasets ' ...
     '(enc_all, trip_all, perc_all, jerk_all) are generated with correct field ' ...
     'structure, and that computeKPPs returns all five KPP structs.'], ...
    '3 replications, 5400 steps/rep';

'VER-SIM-02', 'Seeded Reproducibility', 'Simulation Verification', ...
    'SIM-CAP-011, SIM-CAP-012', ...
    ['Confirms that two independent runs using identical RNG seeds produce ' ...
     'bit-identical output datasets, verifying deterministic replay required ' ...
     'for debugging and regulatory audit.'], ...
    '5 replications × 2 independent runs';

'VER-SIM-03', 'Fully Randomised Test', 'Simulation Verification', ...
    'SIM-CAP-008, SIM-CAP-009, SIM-CAP-012, SIM-CAP-014', ...
    ['Verifies that stochastic elements produce statistically varied outputs ' ...
     'across replications (non-deterministic when seeds differ), that all ' ...
     'per-replication KPP estimates are finite, and that aggregated 95 %% CI ' ...
     'bounds satisfy lo <= mean <= hi.'], ...
    sprintf('%d replications, time-based seed', TP03_REPS);

'VAL-001', 'Safety Metrics Validation', 'Simulation Validation', ...
    'SIM-CAP-005, SIM-CAP-006, SIM-RUN-002', ...
    ['Validates TTC, PET, and minimum separation distance computed by ' ...
     'detectConflicts against closed-form analytical values for four ' ...
     'deterministic scenarios (pedestrian TTC/PET, vehicle TTC, medium ' ...
     'severity classification, dwell-mode suppression). ' ...
     'Pass criteria: error <= 0.05 s (TTC/PET) or 0.05 m (separation).'], ...
    '4 deterministic test cases, direct function call';

'VAL-002', 'Trip Performance Validation', 'Simulation Validation', ...
    'SIM-CAP-007, SIM-MET-001', ...
    ['Validates trip delay calculation in two parts. Part A checks the ' ...
     'delay_pct formula against five exact analytical inputs (tolerance 1e-9). ' ...
     'Part B runs a deterministic simulation (speed_std=0, no agents) and ' ...
     'confirms mean delay is within the time-step quantisation bound (|mean| <= 5 %%).'], ...
    '5 formula cases + 3 simulation replications';

'VAL-003', 'Perception Metrics Validation', 'Simulation Validation', ...
    'SIM-CAP-008, SIM-MET-001', ...
    ['Validates computePerception statistical outputs against analytical ' ...
     'expectations using N=5000 perception calls: detection recall (Bernoulli ' ...
     'mean = cfg.detect_prob, tolerance 0.01), prediction error (Rayleigh ' ...
     'mean = pos_noise_std * sqrt(pi/2), tolerance 0.05 m), and latency ' ...
     '(Gaussian mean, tolerance 5 ms).'], ...
    '5000 perception calls, fixed-state scenario';

'VAL-004', 'Motion Dynamics Validation', 'Simulation Validation', ...
    'SIM-CAP-004, SIM-MET-001', ...
    ['Validates RMS jerk and RMS braking-jerk computed by updateShuttles ' ...
     'against analytical values derived from the same known speed sequence. ' ...
     'Confirms jerk and brake-jerk accumulation counts match step count. ' ...
     'Pass criteria: RMS error < 1e-9 m/s^3; count mismatch = 0.'], ...
    '10-step deterministic speed sequence, cfg.dwell_time = 0';

'VAL-005', 'Monte Carlo Aggregation Validation', 'Simulation Validation', ...
    'SIM-CAP-012, SIM-MET-001', ...
    ['Validates computeKPPs aggregation by supplying synthetic per-replication ' ...
     'data with known analytical means and verifying that the reported 95 %% CI ' ...
     'bounds satisfy lo <= mean <= hi for all five KPPs. Checks for NaN/Inf ' ...
     'in all aggregated statistics.'], ...
    '50 synthetic replications, known analytical ground truth';

'OSV-PCR-01', 'Pedestrian Conflict Rate', 'Objective System Verification', ...
    'KPP-PCR-001', ...
    ['Verifies that the high/medium-severity pedestrian conflict rate remains ' ...
     'at or below the OSV threshold of 0.5 conflicts per 1,000 pedestrian ' ...
     'encounters (0.0005) with 95 %% statistical confidence. ' ...
     'Shared Monte Carlo run with all OSV tests.'], ...
    sprintf('%d replications, shared OSV run', OSV_REPS);

'OSV-IVCR-01', 'Inter-Vehicle Conflict Rate', 'Objective System Verification', ...
    'KPP-IVCR-001', ...
    ['Verifies that the shuttle-to-vehicle conflict rate remains at or below ' ...
     '0.3 conflicts per 1,000 vehicle encounters (0.0003) with 95 %% confidence.'], ...
    sprintf('%d replications, shared OSV run', OSV_REPS);

'OSV-ATD-01', 'Average Trip Delay', 'Objective System Verification', ...
    'KPP-ATD-001', ...
    ['Verifies that mean per-trip delay is <= 10 %% of free-flow travel time ' ...
     'and the 95th-percentile delay <= 40 %%, both with 95 %% statistical ' ...
     'confidence.'], ...
    sprintf('%d replications, shared OSV run', OSV_REPS);

'OSV-SAA-01', 'Situational Awareness Accuracy', 'Objective System Verification', ...
    'KPP-SAA-001', ...
    ['Verifies detection recall >= 0.98, mean prediction error <= 0.5 m at a ' ...
     '3 s horizon, and mean perception latency <= 200 ms, all with 95 %% ' ...
     'statistical confidence.'], ...
    sprintf('%d replications, shared OSV run', OSV_REPS);

'OSV-UTI-01', 'User Trust Index', 'Objective System Verification', ...
    'KPP-UTI-001', ...
    ['Verifies that the composite User Trust Index — a weighted function of ' ...
     'ride-comfort jerk, braking smoothness, and conflict rate — achieves ' ...
     '>= 0.80 with 95 %% statistical confidence.'], ...
    sprintf('%d replications, shared OSV run', OSV_REPS);
};
N = size(TESTS, 1);

%% ── Execute tests ─────────────────────────────────────────────────────────
results   = cell(N, 1);
consoles  = cell(N, 1);
durations = zeros(N, 1);
OSV_START = 9;   % row index of first OSV test
osv_console = '';
osv_results = [];

for i = 1:N
    id   = TESTS{i,1};
    name = TESTS{i,2};
    fprintf('  [%2d/%d]  %-14s  %s ... ', i, N, id, name);
    t0 = tic;

    try
        switch id
            case 'VER-SIM-01'
                [consoles{i}, results{i}] = evalc('tp01_smokeTest()');
            case 'VER-SIM-02'
                [consoles{i}, results{i}] = evalc('tp02_seededRandTest()');
            case 'VER-SIM-03'
                cmd = sprintf('tp03_fullRandTest(''reps'',%d)', TP03_REPS);
                [consoles{i}, results{i}] = evalc(cmd);
            case 'VAL-001'
                [consoles{i}, results{i}] = evalc('val_sim_001_safetyMetrics()');
            case 'VAL-002'
                [consoles{i}, results{i}] = evalc('val_sim_002_tripPerformance()');
            case 'VAL-003'
                [consoles{i}, results{i}] = evalc('val_sim_003_perceptionMetrics()');
            case 'VAL-004'
                [consoles{i}, results{i}] = evalc('val_sim_004_motionDynamics()');
            case 'VAL-005'
                [consoles{i}, results{i}] = evalc('val_sim_005_mcAggregation()');
            otherwise
                % All OSV tests share one MC run
                if isempty(osv_results)
                    cmd = sprintf('osv_all(''reps'',%d)', OSV_REPS);
                    [osv_console, osv_results] = evalc(cmd);
                end
                keys = {'pcr','ivcr','atd','saa','uti'};
                key  = keys{i - OSV_START + 1};
                results{i}  = osv_results.(key);
                consoles{i} = osv_console;
        end
    catch ME
        results{i}  = struct('id',id,'name',name,'pass',false, ...
                             'reasons',{{['EXECUTION ERROR: ' ME.message]}});
        consoles{i} = sprintf('[ERROR] %s\n%s', ME.message, ...
                              getReport(ME,'extended'));
    end

    durations(i) = toc(t0);
    fprintf('%s  (%.1f s)\n', ternary(results{i}.pass,'PASS','FAIL'), durations(i));
end

n_pass = sum(cellfun(@(r) r.pass, results));
n_fail = N - n_pass;
fprintf('\n  %d / %d PASS  |  %d FAIL\n\n', n_pass, N, n_fail);

%% ── Build and write HTML ──────────────────────────────────────────────────
cfg  = getDefaultConfig();
html = buildHtml(TESTS, results, consoles, durations, ...
                 n_pass, n_fail, cfg, FAST, TP03_REPS, OSV_REPS);

fid = fopen(out_file, 'w', 'n', 'UTF-8');
if fid < 0
    error('Cannot open output file: %s', out_file);
end
fprintf(fid, '%s', html);
fclose(fid);

abs_path = fullfile(pwd, out_file);
fprintf('Report saved to:\n  %s\n\n', abs_path);
fprintf('Open in a browser and use File > Print > Save as PDF for the final document.\n\n');
try
    web(abs_path, '-browser');
catch; end
end

%% ═══════════════════════════════════════════════════════════════════════════
%%  HTML generation
%% ═══════════════════════════════════════════════════════════════════════════
function html = buildHtml(TESTS, results, consoles, durations, ...
                          n_pass, n_fail, cfg, FAST, TP03_REPS, OSV_REPS)
N = size(TESTS, 1);
now_str = datestr(now, 'dddd dd mmmm yyyy, HH:MM');
overall = ternary(n_fail==0,'PASS','FAIL');
ov_cls  = ternary(n_fail==0,'pass','fail');

%% CSS + header
html = ['<!DOCTYPE html><html lang="en"><head>' ...
        '<meta charset="UTF-8">' ...
        '<meta name="viewport" content="width=device-width,initial-scale=1">' ...
        '<title>ACMSCS V&amp;V Report</title>' ...
        '<style>' css() '</style>' ...
        '</head><body>'];

%% Cover / title block
html = [html, sprintf(['<div class="cover">' ...
    '<div class="cover-badge %s">%s</div>' ...
    '<h1>Autonomous Campus Mobility Safety &amp; Coordination System</h1>' ...
    '<h2>Verification &amp; Validation Report</h2>' ...
    '<p class="cover-meta">UMBC Campus &nbsp;|&nbsp; KSTM Labs</p>' ...
    '<p class="cover-meta">Generated: %s</p>' ...
    '<p class="cover-meta">Mode: %s &nbsp;|&nbsp; %d / %d tests passed</p>' ...
    '</div>'], ov_cls, overall, now_str, ...
    ternary(FAST,'FAST (reduced reps)','FULL'), n_pass, N)];

%% KPP threshold reference table
html = [html, kppTable(cfg)];

%% Executive summary table
html = [html, '<div class="section">' ...
              '<h2 class="section-title">Executive Summary</h2>' ...
              '<table class="summary-tbl"><thead><tr>' ...
              '<th>Test ID</th><th>Test Name</th><th>Section</th>' ...
              '<th>Duration (s)</th><th>Result</th></tr></thead><tbody>'];

cur_section = '';
for i = 1:N
    r   = results{i};
    sec = TESTS{i,3};
    if ~strcmp(sec, cur_section)
        cur_section = sec;
        html = [html, sprintf('<tr class="sec-row"><td colspan="5">%s</td></tr>', sec)]; %#ok<AGROW>
    end
    cls = ternary(r.pass,'pass','fail');
    html = [html, sprintf(['<tr>' ...
        '<td><a href="#%s" class="id-link">%s</a></td>' ...
        '<td>%s</td><td>%s</td><td>%.1f</td>' ...
        '<td class="%s verdict-cell">%s</td>' ...
        '</tr>'], r.id, r.id, TESTS{i,2}, sec, durations(i), cls, ...
        ternary(r.pass,'PASS','FAIL'))]; %#ok<AGROW>
end
html = [html, '</tbody></table></div>'];

%% Per-test sections
cur_section = '';
for i = 1:N
    r   = results{i};
    sec = TESTS{i,3};

    if ~strcmp(sec, cur_section)
        cur_section = sec;
        html = [html, sprintf('<div class="part-header"><h2>%s</h2></div>', sec)]; %#ok<AGROW>
    end

    cls = ternary(r.pass,'pass','fail');
    html = [html, sprintf('<div class="test-card" id="%s">', r.id)]; %#ok<AGROW>

    % ── Test header
    html = [html, sprintf(['<div class="test-head %s-head">' ...
        '<span class="tid">%s</span>' ...
        '<span class="tname">%s</span>' ...
        '<span class="verdict-badge %s">%s</span>' ...
        '<span class="tdur">%.1f s</span>' ...
        '</div>'], cls, r.id, TESTS{i,2}, cls, ...
        ternary(r.pass,'PASS','FAIL'), durations(i))]; %#ok<AGROW>

    % ── Metadata table (requirements, objective, data)
    html = [html, '<div class="card-body">'];
    html = [html, '<table class="meta-tbl">'];
    html = [html, sprintf('<tr><th>Requirements</th><td>%s</td></tr>', TESTS{i,4})]; %#ok<AGROW>
    html = [html, sprintf('<tr><th>Objective</th><td>%s</td></tr>', TESTS{i,5})]; %#ok<AGROW>
    html = [html, sprintf('<tr><th>Simulation Data</th><td>%s</td></tr>', TESTS{i,6})]; %#ok<AGROW>
    html = [html, '</table>'];

    % ── (1) Captured simulation data + (2) Analysis results
    html = [html, '<h4 class="sub-h">&#9312; Captured Simulation Data &amp; Analysis Results</h4>']; %#ok<AGROW>
    html = [html, '<pre class="console">', escHtml(consoles{i}), '</pre>']; %#ok<AGROW>

    % ── (3) Pass / Fail determination
    html = [html, '<h4 class="sub-h">&#9313; Pass / Fail Determination</h4>']; %#ok<AGROW>
    if r.pass
        html = [html, sprintf(['<p class="det-pass">' ...
            '<span class="verdict-badge pass">PASS</span> &nbsp;' ...
            'This test passed. All acceptance criteria were satisfied within ' ...
            'the specified tolerances and no anomalies were detected.' ...
            '</p>'])]; %#ok<AGROW>
    else
        html = [html, sprintf(['<p class="det-fail">' ...
            '<span class="verdict-badge fail">FAIL</span> &nbsp;' ...
            'This test failed. See failure rationale below.' ...
            '</p>'])]; %#ok<AGROW>
    end

    % ── (4) Failure rationale
    html = [html, '<h4 class="sub-h">&#9314; Failure Rationale / Justification</h4>']; %#ok<AGROW>
    if r.pass
        html = [html, '<p class="no-fail">Not applicable — test passed.</p>']; %#ok<AGROW>
    elseif isfield(r,'reasons') && ~isempty(r.reasons)
        html = [html, '<ul class="fail-list">']; %#ok<AGROW>
        for k = 1:numel(r.reasons)
            html = [html, sprintf('<li>%s</li>', escHtml(r.reasons{k}))]; %#ok<AGROW>
        end
        html = [html, '</ul>']; %#ok<AGROW>
    else
        html = [html, '<p class="no-fail">No detailed reason provided.</p>']; %#ok<AGROW>
    end

    html = [html, '</div></div>']; %#ok<AGROW>  % card-body, test-card
end

html = [html, footer(n_pass, N, n_fail), '</body></html>'];
end

%% ── KPP threshold reference ──────────────────────────────────────────────
function html = kppTable(cfg)
row = @(kpp, desc, fmt, val, src) sprintf( ...
    '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>', ...
    kpp, desc, sprintf(fmt, val), src);
html = ['<div class="section">' ...
    '<h2 class="section-title">KPP Acceptance Thresholds</h2>' ...
    '<table class="kpp-tbl"><thead><tr>' ...
    '<th>KPP</th><th>Description</th><th>Threshold</th><th>Config Field</th>' ...
    '</tr></thead><tbody>' ...
    row('PCR',  'Pedestrian Conflict Rate',        '&le; %.4f conflicts/encounter', cfg.kpp.pcr_max,  'cfg.kpp.pcr_max') ...
    row('IVCR', 'Inter-Vehicle Conflict Rate',     '&le; %.4f conflicts/encounter', cfg.kpp.ivcr_max, 'cfg.kpp.ivcr_max') ...
    row('ATD',  'Average Trip Delay',              '&le; %.1f %%',                  cfg.kpp.atd_max,  'cfg.kpp.atd_max') ...
    row('SAA',  'Situational Awareness (recall)',  '&ge; %.2f',                     cfg.kpp.saa_min,  'cfg.kpp.saa_min') ...
    row('UTI',  'User Trust Index',                '&ge; %.2f',                     cfg.kpp.uti_min,  'cfg.kpp.uti_min') ...
    '</tbody></table></div>'];
end

%% ── Footer ───────────────────────────────────────────────────────────────
function html = footer(n_pass, N, n_fail)
html = sprintf(['<div class="footer">' ...
    '<strong>ACMSCS V&amp;V Report</strong> &nbsp;&mdash;&nbsp; ' ...
    '%d / %d tests passed &nbsp;|&nbsp; %d failed &nbsp;|&nbsp; ' ...
    'Generated by exportVVReport.m &nbsp;|&nbsp; KSTM Labs, UMBC' ...
    '</div>'], n_pass, N, n_fail);
end

%% ── HTML escape ──────────────────────────────────────────────────────────
function s = escHtml(s)
s = strrep(s, '&',  '&amp;');
s = strrep(s, '<',  '&lt;');
s = strrep(s, '>',  '&gt;');
s = strrep(s, '"',  '&quot;');
% Highlight PASS/FAIL in console output
s = strrep(s, '[PASS]', '<span class="c-pass">[PASS]</span>');
s = strrep(s, '[FAIL]', '<span class="c-fail">[FAIL]</span>');
s = strrep(s, 'PASS',   '<span class="c-pass">PASS</span>');
s = strrep(s, 'FAIL',   '<span class="c-fail">FAIL</span>');
end

%% ── CSS ──────────────────────────────────────────────────────────────────
function s = css()
% Build CSS as incremental concatenation to avoid blank-line/vertcat issues.
s = '';
% Reset & base
s = [s, '*{box-sizing:border-box;margin:0;padding:0}'];
s = [s, 'body{font-family:"Segoe UI",Arial,sans-serif;font-size:13px;background:#f4f6f9;color:#222;line-height:1.5}'];
s = [s, 'h1{font-size:22px;font-weight:700;margin-bottom:6px}'];
s = [s, 'h2{font-size:16px;font-weight:600;margin-bottom:10px}'];
s = [s, 'h4{font-size:13px;font-weight:600}'];
s = [s, 'a{color:#1a6fba;text-decoration:none}'];
s = [s, 'a:hover{text-decoration:underline}'];
% Cover
s = [s, '.cover{background:linear-gradient(135deg,#1a3a5c 0%,#0d6efd 100%);color:#fff;padding:48px 60px;margin-bottom:24px}'];
s = [s, '.cover h1{color:#fff;font-size:24px}'];
s = [s, '.cover h2{color:#cce4ff;font-size:17px;font-weight:400;margin:8px 0 18px}'];
s = [s, '.cover-meta{color:#aad4ff;font-size:13px;margin-top:4px}'];
s = [s, '.cover-badge{display:inline-block;padding:5px 18px;border-radius:20px;font-weight:700;font-size:15px;margin-bottom:14px;letter-spacing:1px}'];
s = [s, '.cover-badge.pass{background:#28a745;color:#fff}'];
s = [s, '.cover-badge.fail{background:#dc3545;color:#fff}'];
% Layout
s = [s, '.section{background:#fff;margin:0 24px 18px;padding:20px 24px;border-radius:6px;box-shadow:0 1px 4px rgba(0,0,0,.08)}'];
s = [s, '.section-title{font-size:15px;font-weight:700;color:#1a3a5c;border-bottom:2px solid #0d6efd;padding-bottom:6px;margin-bottom:14px}'];
s = [s, '.part-header{background:#1a3a5c;color:#fff;padding:10px 24px;margin:24px 0 0}'];
s = [s, '.part-header h2{color:#fff;font-size:14px;font-weight:600;margin:0}'];
% Summary table
s = [s, '.summary-tbl{width:100%;border-collapse:collapse;font-size:12px}'];
s = [s, '.summary-tbl th{background:#1a3a5c;color:#fff;padding:7px 10px;text-align:left}'];
s = [s, '.summary-tbl td{padding:6px 10px;border-bottom:1px solid #e8ecf0}'];
s = [s, '.summary-tbl tr:hover td{background:#f0f5ff}'];
s = [s, '.sec-row td{background:#e8ecf0;font-weight:600;color:#1a3a5c;padding:4px 10px;font-size:11px;letter-spacing:.5px}'];
s = [s, '.id-link{font-weight:600}'];
s = [s, '.verdict-cell{font-weight:700;text-align:center}'];
% Test cards
s = [s, '.test-card{background:#fff;margin:0 24px 16px;border-radius:6px;box-shadow:0 1px 4px rgba(0,0,0,.10);overflow:hidden}'];
s = [s, '.test-head{display:flex;align-items:center;gap:12px;padding:10px 16px}'];
s = [s, '.pass-head{border-left:5px solid #28a745;background:#f0fff4}'];
s = [s, '.fail-head{border-left:5px solid #dc3545;background:#fff5f5}'];
s = [s, '.tid{font-size:13px;font-weight:700;color:#1a3a5c;min-width:110px}'];
s = [s, '.tname{flex:1;font-size:13px;color:#333}'];
s = [s, '.tdur{font-size:11px;color:#666;margin-left:auto}'];
s = [s, '.verdict-badge{padding:3px 10px;border-radius:12px;font-weight:700;font-size:11px;letter-spacing:.5px}'];
s = [s, '.verdict-badge.pass{background:#28a745;color:#fff}'];
s = [s, '.verdict-badge.fail{background:#dc3545;color:#fff}'];
s = [s, '.card-body{padding:14px 18px}'];
% Metadata table
s = [s, '.meta-tbl{width:100%;border-collapse:collapse;margin-bottom:14px;font-size:12px;border:1px solid #dde3ec}'];
s = [s, '.meta-tbl th{background:#edf2fb;width:130px;padding:7px 10px;font-weight:600;color:#1a3a5c;vertical-align:top;border:1px solid #dde3ec;text-align:left}'];
s = [s, '.meta-tbl td{padding:7px 10px;border:1px solid #dde3ec;color:#333}'];
% KPP table
s = [s, '.kpp-tbl{width:100%;border-collapse:collapse;font-size:12px}'];
s = [s, '.kpp-tbl th{background:#1a3a5c;color:#fff;padding:7px 10px;text-align:left}'];
s = [s, '.kpp-tbl td{padding:6px 10px;border-bottom:1px solid #e8ecf0}'];
s = [s, '.kpp-tbl tr:nth-child(even) td{background:#f8f9fc}'];
% Sub-headings
s = [s, '.sub-h{font-size:12px;font-weight:700;color:#1a3a5c;margin:14px 0 6px;padding-bottom:3px;border-bottom:1px solid #e0e8f4}'];
% Console output
s = [s, 'pre.console{background:#1e1e2e;color:#cdd6f4;padding:12px 14px;border-radius:4px;font-size:10.5px;font-family:"Courier New",monospace;white-space:pre-wrap;word-break:break-word;max-height:420px;overflow-y:auto;margin-bottom:10px;line-height:1.45}'];
s = [s, '.c-pass{color:#a6e3a1;font-weight:bold}'];
s = [s, '.c-fail{color:#f38ba8;font-weight:bold}'];
% Determination / rationale
s = [s, '.det-pass{padding:8px 12px;background:#f0fff4;border-radius:4px;border:1px solid #c3e6cb;display:flex;align-items:center;gap:8px}'];
s = [s, '.det-fail{padding:8px 12px;background:#fff5f5;border-radius:4px;border:1px solid #f5c6cb;display:flex;align-items:center;gap:8px}'];
s = [s, '.no-fail{color:#6c757d;font-style:italic;font-size:12px}'];
s = [s, '.fail-list{margin-left:18px;color:#dc3545;font-size:12px}'];
s = [s, '.fail-list li{margin-bottom:4px}'];
% Verdict colours
s = [s, 'td.pass{color:#28a745} td.fail{color:#dc3545}'];
% Footer
s = [s, '.footer{text-align:center;padding:20px;color:#888;font-size:11px;margin-top:8px}'];
% Print media
s = [s, '@media print{'];
s = [s, 'body{background:#fff}'];
s = [s, 'pre.console{max-height:none;overflow:visible}'];
s = [s, '.test-card,.section{box-shadow:none;border:1px solid #ccc}'];
s = [s, '.cover{-webkit-print-color-adjust:exact;print-color-adjust:exact}'];
s = [s, '.verdict-badge,.c-pass,.c-fail,.pass-head,.fail-head{-webkit-print-color-adjust:exact;print-color-adjust:exact}'];
s = [s, '}'];
end

%% ── Utility ──────────────────────────────────────────────────────────────
function s = ternary(cond, a, b)
    if cond; s = a; else; s = b; end
end
