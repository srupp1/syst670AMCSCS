function vvDashboard(varargin)
% vvDashboard  Live tabbed V&V test suite dashboard for ACMSCS simulation.
%
% Opens a UI figure with one tab per test (Summary + 13 test tabs).
% Each test runs in sequence; console output is captured via evalc and
% displayed in a scrollable textarea alongside a metrics/status panel.
%
% Usage:
%   vvDashboard          % full run (TP-03: 30 reps, OSV: 100 reps)
%   vvDashboard('fast')  % quick run (TP-03: 10 reps, OSV: 30 reps)

%% ── Parse arguments ──────────────────────────────────────────────────────
FAST_MODE = (nargin > 0 && strcmpi(varargin{1}, 'fast'));
TP03_REPS = 30;
OSV_REPS  = 100;
if FAST_MODE
    TP03_REPS = 10;
    OSV_REPS  = 30;
end

%% ── Colour palette (dark theme) ─────────────────────────────────────────
C_BG        = [0.12 0.12 0.14];   % main background
C_HEADER    = [0.08 0.08 0.10];   % header bar
C_TAB_BG    = [0.15 0.15 0.18];   % tab panel background
C_CONSOLE   = [0.05 0.05 0.07];   % console textarea
C_METRICS   = [0.10 0.12 0.15];   % metrics textarea
C_TEXT      = [0.90 0.90 0.92];   % normal text
C_DIM       = [0.50 0.50 0.55];   % dimmed / labels
C_PASS      = [0.20 0.80 0.40];   % green
C_FAIL      = [0.95 0.30 0.25];   % red
C_RUN       = [0.95 0.75 0.10];   % amber / running
C_BADGE_BG  = [0.20 0.20 0.24];   % badge background

%% ── Figure ───────────────────────────────────────────────────────────────
FIG_W = 1460;  FIG_H = 870;
fig = uifigure('Name', 'ACMSCS V&V Dashboard', ...
    'Position', [60 60 FIG_W FIG_H], ...
    'Color', C_BG, ...
    'Resize', 'off');

%% ── Header bar ───────────────────────────────────────────────────────────
HDR_H = 38;
hdr = uipanel(fig, 'Position', [0 FIG_H-HDR_H FIG_W HDR_H], ...
    'BackgroundColor', C_HEADER, 'BorderType', 'none');

uilabel(hdr, 'Position', [12 6 400 26], ...
    'Text', 'ACMSCS  V&V  Test  Suite  Dashboard', ...
    'FontSize', 15, 'FontWeight', 'bold', ...
    'FontColor', C_TEXT, 'BackgroundColor', C_HEADER);

lbl_overall = uilabel(hdr, 'Position', [460 6 160 26], ...
    'Text', 'Overall:  PENDING', ...
    'FontSize', 12, 'FontWeight', 'bold', ...
    'FontColor', C_RUN, 'BackgroundColor', C_HEADER);

lbl_elapsed = uilabel(hdr, 'Position', [650 6 200 26], ...
    'Text', 'Elapsed: 0.0 s', ...
    'FontSize', 11, ...
    'FontColor', C_DIM, 'BackgroundColor', C_HEADER);

uilabel(hdr, 'Position', [1260 6 180 26], ...
    'Text', ternary(FAST_MODE, 'Mode: FAST', 'Mode: FULL'), ...
    'FontSize', 11, 'HorizontalAlignment', 'right', ...
    'FontColor', C_DIM, 'BackgroundColor', C_HEADER);

%% ── Tab group ────────────────────────────────────────────────────────────
TAB_AREA_H = FIG_H - HDR_H;
tg = uitabgroup(fig, 'Position', [0 0 FIG_W TAB_AREA_H]);

% ── Test metadata ─────────────────────────────────────────────────────────
% Each row: {tab_label, short_id, run_cmd_type, display_name}
% run_cmd_type: 'tp01','tp02','tp03','val001'..'val005','osv' (shared)
TESTS = {
    ' TP-01 ',   'TP-01',   'tp01',   'TP-01: Smoke Test';
    ' TP-02 ',   'TP-02',   'tp02',   'TP-02: Seeded Reproducibility';
    ' TP-03 ',   'TP-03',   'tp03',   'TP-03: Fully Randomized';
    ' VAL-001 ', 'VAL-001', 'val001', 'VAL-SIM-001: Safety Metrics';
    ' VAL-002 ', 'VAL-002', 'val002', 'VAL-SIM-002: Trip Performance';
    ' VAL-003 ', 'VAL-003', 'val003', 'VAL-SIM-003: Perception Metrics';
    ' VAL-004 ', 'VAL-004', 'val004', 'VAL-SIM-004: Motion Dynamics';
    ' VAL-005 ', 'VAL-005', 'val005', 'VAL-SIM-005: MC Aggregation';
    ' OSV-PCR ',  'OSV-PCR',  'osv_pcr',  'OSV-PCR: Pedestrian Conflict Rate';
    ' OSV-IVCR ', 'OSV-IVCR', 'osv_ivcr', 'OSV-IVCR: Inter-Vehicle Conflict Rate';
    ' OSV-ATD ',  'OSV-ATD',  'osv_atd',  'OSV-ATD: Average Trip Delay';
    ' OSV-SAA ',  'OSV-SAA',  'osv_saa',  'OSV-SAA: Situation Awareness Accuracy';
    ' OSV-UTI ',  'OSV-UTI',  'osv_uti',  'OSV-UTI: User Trust Index';
};
N_TESTS = size(TESTS, 1);

%% ── Build Summary tab ────────────────────────────────────────────────────
tab_sum = uitab(tg, 'Title', ' Summary ', 'BackgroundColor', C_TAB_BG);

% Table columns: ID | Name | Pass/Fail | Duration | Fail Reason
sum_cols = {'ID','Test Name','Result','Duration (s)','Notes'};
sum_data = repmat({'—'}, N_TESTS, numel(sum_cols));
for i = 1:N_TESTS
    sum_data{i,1} = TESTS{i,2};
    sum_data{i,2} = TESTS{i,4};
    sum_data{i,3} = 'PENDING';
    sum_data{i,4} = '—';
    sum_data{i,5} = '';
end

tbl = uitable(tab_sum, ...
    'Position', [8 8 838 TAB_AREA_H-54], ...
    'Data', sum_data, ...
    'ColumnName', sum_cols, ...
    'ColumnWidth', {70, 250, 80, 90, 265}, ...
    'FontSize', 11, ...
    'BackgroundColor', [C_CONSOLE; C_TAB_BG], ...
    'ForegroundColor', C_TEXT, ...
    'RowName', {});

uilabel(tab_sum, 'Position', [874 TAB_AREA_H-46 200 22], ...
    'Text', 'Failure Log', 'FontSize', 11, 'FontWeight', 'bold', ...
    'FontColor', C_DIM, 'BackgroundColor', C_TAB_BG);

txt_faillog = uitextarea(tab_sum, ...
    'Position', [874 8 578 TAB_AREA_H-54], ...
    'Value', {'(failures will appear here)'}, ...
    'FontName', 'Courier New', 'FontSize', 10, ...
    'BackgroundColor', C_CONSOLE, 'FontColor', C_FAIL, ...
    'Editable', 'off');

%% ── Build individual test tabs ───────────────────────────────────────────
USABLE_H = TAB_AREA_H - 70;   % pixels inside tab below status strip

tabs       = gobjects(N_TESTS, 1);
lbl_status = gobjects(N_TESTS, 1);
lbl_timing = gobjects(N_TESTS, 1);
txt_cons   = gobjects(N_TESTS, 1);
txt_metr   = gobjects(N_TESTS, 1);

STRIP_H = 64;
CONS_W  = 895;
METR_X  = 946;
METR_W  = FIG_W - METR_X - 8;

for i = 1:N_TESTS
    tabs(i) = uitab(tg, 'Title', TESTS{i,1}, 'BackgroundColor', C_TAB_BG);

    % Status strip
    uipanel(tabs(i), 'Position', [0 USABLE_H FIG_W STRIP_H], ...
        'BackgroundColor', C_BADGE_BG, 'BorderType', 'none');

    lbl_status(i) = uilabel(tabs(i), ...
        'Position', [12 USABLE_H+14 500 34], ...
        'Text', sprintf('[%s]  %s  —  PENDING', TESTS{i,2}, TESTS{i,4}), ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'FontColor', C_RUN, 'BackgroundColor', C_BADGE_BG);

    lbl_timing(i) = uilabel(tabs(i), ...
        'Position', [560 USABLE_H+18 300 26], ...
        'Text', 'Not started', ...
        'FontSize', 11, ...
        'FontColor', C_DIM, 'BackgroundColor', C_BADGE_BG);

    % Console area
    uilabel(tabs(i), 'Position', [8 USABLE_H-22 200 18], ...
        'Text', 'Console Output', 'FontSize', 10, 'FontWeight', 'bold', ...
        'FontColor', C_DIM, 'BackgroundColor', C_TAB_BG);

    txt_cons(i) = uitextarea(tabs(i), ...
        'Position', [8 8 CONS_W USABLE_H-28], ...
        'Value', {sprintf('[ %s ]  Waiting to run…', TESTS{i,2})}, ...
        'FontName', 'Courier New', 'FontSize', 10, ...
        'BackgroundColor', C_CONSOLE, 'FontColor', C_TEXT, ...
        'Editable', 'off');

    % Metrics area
    uilabel(tabs(i), 'Position', [METR_X USABLE_H-22 200 18], ...
        'Text', 'Test Result & Metrics', 'FontSize', 10, 'FontWeight', 'bold', ...
        'FontColor', C_DIM, 'BackgroundColor', C_TAB_BG);

    txt_metr(i) = uitextarea(tabs(i), ...
        'Position', [METR_X 8 METR_W USABLE_H-28], ...
        'Value', {'—'}, ...
        'FontName', 'Courier New', 'FontSize', 10, ...
        'BackgroundColor', C_METRICS, 'FontColor', C_TEXT, ...
        'Editable', 'off');
end

%% ── Run tests ────────────────────────────────────────────────────────────
t_wall = tic;
pass_count  = 0;
fail_count  = 0;
osv_results = [];   % shared OSV MC result (populated on first OSV tab)
osv_console = '';   % shared OSV console output

for i = 1:N_TESTS
    if ~isvalid(fig); return; end

    % Switch to this tab so user can see it running
    tg.SelectedTab = tabs(i);

    % Mark as RUNNING
    lbl_status(i).Text      = sprintf('[%s]  %s  —  RUNNING…', TESTS{i,2}, TESTS{i,4});
    lbl_status(i).FontColor = C_RUN;
    lbl_timing(i).Text      = 'Running…';
    txt_cons(i).Value       = {sprintf('[ %s ]  Running…', TESTS{i,2})};
    setTableRow(tbl, i, 'RUNNING', '…', '', C_RUN);
    drawnow;

    t_test = tic;

    %% ── Execute the test ─────────────────────────────────────────────────
    result  = [];
    console = '';

    try
        cmd_type = TESTS{i,3};
        switch cmd_type
            case 'tp01'
                [console, result] = evalc('tp01_smokeTest()');

            case 'tp02'
                [console, result] = evalc('tp02_seededRandTest()');

            case 'tp03'
                [console, result] = evalc(sprintf('tp03_fullRandTest(''reps'',%d)', TP03_REPS));

            case 'val001'
                [console, result] = evalc('val_sim_001_safetyMetrics()');

            case 'val002'
                [console, result] = evalc('val_sim_002_tripPerformance()');

            case 'val003'
                [console, result] = evalc('val_sim_003_perceptionMetrics()');

            case 'val004'
                [console, result] = evalc('val_sim_004_motionDynamics()');

            case 'val005'
                [console, result] = evalc('val_sim_005_mcAggregation()');

            case {'osv_pcr','osv_ivcr','osv_atd','osv_saa','osv_uti'}
                % OSV tests share one MC run — only execute on first OSV tab
                osv_idx_start = find(strcmp(TESTS(:,3), 'osv_pcr'), 1);
                if i == osv_idx_start || isempty(osv_results)
                    % Run the shared MC (or re-run if somehow missed)
                    [osv_console, osv_results] = evalc( ...
                        sprintf('osv_all(''reps'',%d)', OSV_REPS));
                end
                % Annotate non-first OSV tabs with cross-reference note
                if i ~= osv_idx_start
                    console = ['(shared OSV run — full log in OSV-PCR tab)', char(10), osv_console];
                else
                    console = osv_console;
                end

                % Map result for this specific OSV tab
                osv_key = strrep(cmd_type, 'osv_', '');
                result  = osv_results.(osv_key);

            otherwise
                error('Unknown cmd_type: %s', cmd_type);
        end
    catch ME
        result  = struct('id', TESTS{i,2}, 'name', TESTS{i,4}, ...
                         'pass', false, 'reasons', {{ME.message}});
        console = [console, sprintf('\n[ERROR] %s\n', ME.message)];
    end

    elapsed_test = toc(t_test);
    elapsed_wall = toc(t_wall);

    %% ── Update UI ────────────────────────────────────────────────────────
    if ~isvalid(fig); return; end

    passed = ~isempty(result) && result.pass;

    % Status strip
    if passed
        status_txt   = sprintf('[%s]  %s  —  PASS', TESTS{i,2}, TESTS{i,4});
        status_color = C_PASS;
    else
        status_txt   = sprintf('[%s]  %s  —  FAIL', TESTS{i,2}, TESTS{i,4});
        status_color = C_FAIL;
    end
    lbl_status(i).Text      = status_txt;
    lbl_status(i).FontColor = status_color;
    lbl_timing(i).Text      = sprintf('%.2f s', elapsed_test);

    % Console textarea
    console_lines = strsplit(console, '\n');
    txt_cons(i).Value = console_lines;

    % Metrics textarea
    metrics_lines = buildMetrics(result, elapsed_test);
    txt_metr(i).Value = metrics_lines;

    % Summary table
    if passed
        pass_count = pass_count + 1;
        setTableRow(tbl, i, 'PASS', sprintf('%.2f', elapsed_test), '', C_PASS);
    else
        fail_count = fail_count + 1;
        first_reason = '';
        if ~isempty(result) && isfield(result,'reasons') && ~isempty(result.reasons)
            first_reason = result.reasons{1};
        end
        setTableRow(tbl, i, 'FAIL', sprintf('%.2f', elapsed_test), first_reason, C_FAIL);
        appendFail(txt_faillog, TESTS{i,2}, result);
    end

    % Update overall header
    lbl_elapsed.Text = sprintf('Elapsed: %.1f s', elapsed_wall);
    updateOverall(lbl_overall, pass_count, fail_count, N_TESTS, i, C_PASS, C_FAIL, C_RUN);
    drawnow;
end

%% ── Final overall status ─────────────────────────────────────────────────
if ~isvalid(fig); return; end
tg.SelectedTab = tab_sum;
elapsed_wall = toc(t_wall);
lbl_elapsed.Text = sprintf('Elapsed: %.1f s  |  Done', elapsed_wall);
if fail_count == 0
    lbl_overall.Text      = sprintf('Overall:  ALL PASS  (%d/%d)', pass_count, N_TESTS);
    lbl_overall.FontColor = C_PASS;
else
    lbl_overall.Text      = sprintf('Overall:  %d FAIL  /  %d PASS', fail_count, pass_count);
    lbl_overall.FontColor = C_FAIL;
end
drawnow;

end % vvDashboard

%% ═══════════════════════════════════════════════════════════════════════════
%%  Helper functions
%% ═══════════════════════════════════════════════════════════════════════════

function lines = buildMetrics(result, elapsed)
% Build metrics panel content from a result struct.
lines = {};
if isempty(result)
    lines{end+1} = 'No result returned.';
    return;
end
lines{end+1} = sprintf('ID     : %s', result.id);
lines{end+1} = sprintf('Name   : %s', result.name);
lines{end+1} = sprintf('Result : %s', ternary(result.pass, 'PASS', 'FAIL'));
lines{end+1} = sprintf('Time   : %.3f s', elapsed);
lines{end+1} = '';

if ~result.pass && isfield(result, 'reasons') && ~isempty(result.reasons)
    lines{end+1} = 'Failure reasons:';
    for k = 1:numel(result.reasons)
        lines{end+1} = sprintf('  [%d] %s', k, result.reasons{k});
    end
else
    lines{end+1} = 'All checks passed.';
end

% Extra KPP/metric fields if present
extra_fields = {'PCR','IVCR','ATD','SAA_recall','UTI', ...
                'pcr_mean','ivcr_mean','atd_mean','recall','uti_mean', ...
                'value','threshold','margin'};
found_extra = false;
for k = 1:numel(extra_fields)
    f = extra_fields{k};
    if isfield(result, f)
        if ~found_extra
            lines{end+1} = '';
            lines{end+1} = 'Metrics:';
            found_extra = true;
        end
        v = result.(f);
        if isnumeric(v)
            lines{end+1} = sprintf('  %-14s = %.6g', f, v);
        elseif ischar(v) || isstring(v)
            lines{end+1} = sprintf('  %-14s = %s', f, v);
        end
    end
end
end

% ─────────────────────────────────────────────────────────────────────────────
function setTableRow(tbl, row, result_str, dur_str, note_str, clr) %#ok<INUSL>
% Update a summary table row.
d = tbl.Data;
d{row, 3} = result_str;
d{row, 4} = dur_str;
if ~isempty(note_str)
    d{row, 5} = note_str;
end
tbl.Data = d;
end

% ─────────────────────────────────────────────────────────────────────────────
function updateOverall(lbl, n_pass, n_fail, n_total, n_done, c_pass, c_fail, c_run)
remaining = n_total - n_done;
if remaining > 0
    lbl.Text      = sprintf('Overall:  %d pass  %d fail  (%d pending)', ...
                             n_pass, n_fail, remaining);
    lbl.FontColor = c_run;
elseif n_fail == 0
    lbl.Text      = sprintf('Overall:  ALL PASS  (%d/%d)', n_pass, n_total);
    lbl.FontColor = c_pass;
else
    lbl.Text      = sprintf('Overall:  %d FAIL  /  %d PASS', n_fail, n_pass);
    lbl.FontColor = c_fail;
end
end

% ─────────────────────────────────────────────────────────────────────────────
function appendFail(txt, test_id, result)
% Append failure info to the summary failure log textarea.
existing = txt.Value;
if numel(existing) == 1 && strcmp(existing{1}, '(failures will appear here)')
    existing = {};
end
existing{end+1} = sprintf('─── %s ─────────────────────────', test_id);
if isfield(result, 'reasons') && ~isempty(result.reasons)
    for k = 1:numel(result.reasons)
        existing{end+1} = sprintf('  %s', result.reasons{k});
    end
else
    existing{end+1} = '  (no reason provided)';
end
existing{end+1} = '';
txt.Value = existing;
end

% ─────────────────────────────────────────────────────────────────────────────
function s = ternary(cond, a, b)
if cond; s = a; else; s = b; end
end
