function sensitivityAnalysis(varargin)
% sensitivityAnalysis  One-At-a-Time (OAT) sensitivity analysis for ACMSCS
%
% Sweeps 7 input parameters across 5 levels (±50%, ±25%, baseline) while
% holding all others fixed. Runs Monte Carlo for each scenario and reports:
%   - Normalized Sensitivity Indices (NSI) per KPP
%   - Tornado plots (one subplot per KPP, parameters ranked by impact)
%   - sensitivity_results.csv
%
% Normalized Sensitivity Index:
%   NSI = (ΔY / Y₀) / (Δθ / θ₀)
%   Values near 0 → KPP insensitive to that parameter
%   |NSI| > 1     → amplified sensitivity
%
% Usage:
%   sensitivityAnalysis              % 30 reps/scenario (~37 scenarios)
%   sensitivityAnalysis('reps', 50)  % more reps, more stable CIs
%   sensitivityAnalysis('reps', 10)  % quick smoke check
%
% The baseline scenario is run once and reused for all parameter sweeps.

p = inputParser;
addParameter(p, 'reps', 30, @(x) isnumeric(x) && x >= 5);
parse(p, varargin{:});
N_REPS_SA = p.Results.reps;

fprintf('\n=========================================\n');
fprintf('  ACMSCS OAT Sensitivity Analysis\n');
fprintf('  %d reps/scenario  |  %s\n', N_REPS_SA, datestr(now,'yyyy-mm-dd HH:MM'));
fprintf('=========================================\n\n');

%% ── Environment & baseline config ─────────────────────────────────────────
cfg_base               = getDefaultConfig();
cfg_base.n_replications = N_REPS_SA;
env                    = loadEnvironment('G.mat', cfg_base);

%% ── Parameter sweep table ─────────────────────────────────────────────────
% Columns: field | display label | levels | level_type ('scale' | 'abs')
%   'scale' : cfg.(field) = baseline * level_value
%   'abs'   : cfg.(field) = level_value  (used when baseline * scale would
%             exceed physical bounds or requires integer values)
SWEEP = {
    'uti_w_jerk',        'UTI jerk weight',      [0.50 0.75 1.00 1.25 1.50], 'scale';
    'uti_w_brake',       'UTI brake weight',     [0.50 0.75 1.00 1.25 1.50], 'scale';
    'uti_w_consistency', 'UTI consist. weight',  [0.50 0.75 1.00 1.25 1.50], 'scale';
    'latency_mean',      'Sensing latency',      [0.50 0.75 1.00 1.25 1.50], 'scale';
    'pred_horizon',      'Prediction horizon',   [0.50 0.75 1.00 1.25 1.50], 'scale';
    'weather_std',       'Weather variation',    [0.50 0.75 1.00 1.25 1.50], 'scale';
    'n_shuttles',        'Fleet size',           [1 2 3 4 5],                'abs';
};

n_params  = size(SWEEP, 1);
n_levels  = size(SWEEP{1,3}, 2);   % 5 levels per parameter
KPP_NAMES = {'PCR','IVCR','ATD','SAA_recall','UTI'};
n_kpps    = numel(KPP_NAMES);

% Baseline values for each parameter (used in NSI denominator)
base_vals = cellfun(@(f) cfg_base.(f), SWEEP(:,1));

% Absolute parameter value for each (field, level) combination
param_vals = zeros(n_params, n_levels);
for pi = 1:n_params
    for li = 1:n_levels
        if strcmp(SWEEP{pi,4}, 'scale')
            param_vals(pi,li) = base_vals(pi) * SWEEP{pi,3}(li);
        else
            param_vals(pi,li) = SWEEP{pi,3}(li);
        end
    end
end

% Index of the baseline level for each parameter
base_level_idx = zeros(n_params, 1);
for pi = 1:n_params
    [~, base_level_idx(pi)] = min(abs(param_vals(pi,:) - base_vals(pi)));
end

%% ── Baseline scenario ──────────────────────────────────────────────────────
n_total = 1 + n_params * (n_levels - 1);   % shared baseline + perturbed runs
fprintf('Total scenarios: %d   (1 baseline + %d perturbed)\n', n_total, n_total-1);
fprintf('Total replications: ~%d\n\n', n_total * N_REPS_SA);

fprintf('[0/%d] Running baseline scenario...\n', n_total);
t_start_all = tic;
kpp_base  = runScenario(cfg_base, env);
base_kpps = extractMeans(kpp_base, KPP_NAMES);
fprintf('  Baseline KPPs: PCR=%.4f  IVCR=%.4f  ATD=%.2f%%  SAA=%.4f  UTI=%.4f\n\n', ...
    base_kpps(1), base_kpps(2), base_kpps(3), base_kpps(4), base_kpps(5));

%% ── Perturbed scenarios ────────────────────────────────────────────────────
% kpp_means(pi, li, ki) = KPP mean for parameter pi, level li, KPP ki
kpp_means = nan(n_params, n_levels, n_kpps);

% Fill in cached baseline values
for pi = 1:n_params
    kpp_means(pi, base_level_idx(pi), :) = base_kpps;
end

scenario_count = 1;
for pi = 1:n_params
    for li = 1:n_levels
        if li == base_level_idx(pi)
            continue;   % already cached
        end
        scenario_count = scenario_count + 1;

        cfg_p          = cfg_base;
        cfg_p.(SWEEP{pi,1}) = param_vals(pi,li);
        if strcmp(SWEEP{pi,1}, 'n_shuttles')
            cfg_p.n_shuttles = round(cfg_p.n_shuttles);
        end

        fprintf('[%d/%d] %s = %.4g  (baseline = %.4g)\n', ...
            scenario_count, n_total, SWEEP{pi,1}, param_vals(pi,li), base_vals(pi));

        kpp_s = runScenario(cfg_p, env);
        kpp_means(pi, li, :) = extractMeans(kpp_s, KPP_NAMES);
    end
    fprintf('\n');
end

elapsed = toc(t_start_all);
fprintf('All scenarios complete in %.1f s  (%.1f s/scenario)\n\n', ...
    elapsed, elapsed/scenario_count);

%% ── Normalized Sensitivity Indices ────────────────────────────────────────
% NSI at each non-baseline level; report max |NSI| across levels
% NSI = (dY/Y0) / (dX/X0)
nsi = zeros(n_params, n_kpps);   % max |NSI| per param per KPP

for pi = 1:n_params
    for ki = 1:n_kpps
        Y0    = base_kpps(ki);
        theta0 = base_vals(pi);
        if abs(Y0) < 1e-9 || abs(theta0) < 1e-9
            continue;
        end
        nsi_levels = zeros(1, n_levels);
        for li = 1:n_levels
            if li == base_level_idx(pi); continue; end
            dY     = kpp_means(pi, li, ki) - Y0;
            dtheta = param_vals(pi, li) - theta0;
            if abs(dtheta) < 1e-12; continue; end
            nsi_levels(li) = (dY / Y0) / (dtheta / theta0);
        end
        nsi(pi, ki) = max(abs(nsi_levels));
    end
end

%% ── Console table ─────────────────────────────────────────────────────────
fprintf('Normalized Sensitivity Indices  (max |NSI| across all levels)\n');
fprintf('%-22s', '');
for ki = 1:n_kpps
    fprintf('  %-9s', KPP_NAMES{ki});
end
fprintf('\n');
fprintf('%s\n', repmat('-', 1, 22 + n_kpps*11));
for pi = 1:n_params
    fprintf('%-22s', SWEEP{pi,2});
    for ki = 1:n_kpps
        fprintf('  %9.4f', nsi(pi,ki));
    end
    fprintf('\n');
end
fprintf('\n');

%% ── CSV export ─────────────────────────────────────────────────────────────
csv_file = 'sensitivity_results.csv';
fid = fopen(csv_file, 'w');
fprintf(fid, 'Parameter,Field,Level,Value');
for ki = 1:n_kpps
    fprintf(fid, ',%s', KPP_NAMES{ki});
end
fprintf(fid, '\n');
for pi = 1:n_params
    for li = 1:n_levels
        base_str = '';
        if li == base_level_idx(pi); base_str = ' (baseline)'; end
        fprintf(fid, '%s,%s,%d,%.6g%s', ...
            SWEEP{pi,2}, SWEEP{pi,1}, li, param_vals(pi,li), base_str);
        for ki = 1:n_kpps
            fprintf(fid, ',%.6f', kpp_means(pi, li, ki));
        end
        fprintf(fid, '\n');
    end
end
fclose(fid);
fprintf('Results saved to %s\n\n', csv_file);

%% ── Tornado plots ──────────────────────────────────────────────────────────
plotTornado(kpp_means, base_kpps, param_vals, base_level_idx, ...
            SWEEP(:,2), KPP_NAMES, n_params, n_levels, n_kpps);

end  % sensitivityAnalysis

% ═══════════════════════════════════════════════════════════════════════════
function kpps = runScenario(cfg, env)
% Run Monte Carlo simulation for the given config without a dashboard.
    n = cfg.n_replications;
    enc_all  = cell(n,1);
    trip_all = cell(n,1);
    perc_all = cell(n,1);
    jerk_all = cell(n,1);

    for rep = 1:n
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
    end

    kpps = computeKPPs(enc_all, trip_all, perc_all, jerk_all, cfg, env);
end

% ─────────────────────────────────────────────────────────────────────────────
function vals = extractMeans(kpps, kpp_names)
% Return KPP means as a numeric row vector in the order of kpp_names.
    vals = zeros(1, numel(kpp_names));
    for i = 1:numel(kpp_names)
        vals(i) = kpps.(kpp_names{i}).mean;
    end
end

% ─────────────────────────────────────────────────────────────────────────────
function plotTornado(kpp_means, base_kpps, param_vals, base_level_idx, ...
                     param_labels, kpp_names, n_params, n_levels, n_kpps)
% Draw one tornado subplot per KPP.
% Each bar spans [min KPP value, max KPP value] across all sweep levels,
% split at the baseline into a "decrease" segment and "increase" segment.

BG   = [0.12 0.12 0.15];
FG   = [0.92 0.92 0.92];
C_LO = [0.25 0.55 0.95];   % blue  = lower value
C_HI = [0.95 0.40 0.25];   % red   = higher value
C_BL = [0.85 0.85 0.30];   % yellow = baseline marker

fig = figure('Name','OAT Sensitivity — Tornado Charts', ...
    'Color', BG, ...
    'Position', [60 60 1400 760], ...
    'NumberTitle','off');

% "Better" direction for each KPP (used for axis label)
better_dir = {'lower','lower','lower','higher','higher'};

% Layout: 2 rows × 3 cols, last cell empty
layout_pos = {[1,1],[1,2],[1,3],[2,1],[2,2]};

for ki = 1:n_kpps
    row = layout_pos{ki}(1);
    col = layout_pos{ki}(2);
    ax  = subplot(2, 3, (row-1)*3 + col);
    set(ax, 'Color', BG, 'XColor', FG, 'YColor', FG, ...
        'GridColor', [0.3 0.3 0.3], 'GridAlpha', 0.4, ...
        'FontSize', 8, 'TickDir','out');
    hold(ax,'on'); grid(ax,'on');

    Y0 = base_kpps(ki);

    % Compute per-parameter range for sorting
    ranges = zeros(n_params,1);
    for pi = 1:n_params
        v = squeeze(kpp_means(pi, :, ki));
        ranges(pi) = max(v) - min(v);
    end
    [~, order] = sort(ranges, 'ascend');   % smallest impact at bottom

    BAR_H = 0.38;

    for rank = 1:n_params
        pi      = order(rank);
        v       = squeeze(kpp_means(pi, :, ki));
        v_min   = min(v);
        v_max   = max(v);

        % Left (decrease from baseline) segment
        if v_min < Y0
            patch(ax, [v_min Y0 Y0 v_min], ...
                  [rank-BAR_H rank-BAR_H rank+BAR_H rank+BAR_H], ...
                  C_LO, 'EdgeColor','none', 'FaceAlpha', 0.85);
        end
        % Right (increase from baseline) segment
        if v_max > Y0
            patch(ax, [Y0 v_max v_max Y0], ...
                  [rank-BAR_H rank-BAR_H rank+BAR_H rank+BAR_H], ...
                  C_HI, 'EdgeColor','none', 'FaceAlpha', 0.85);
        end
        % Level dots
        for li = 1:n_levels
            if ~isnan(kpp_means(pi,li,ki))
                plot(ax, kpp_means(pi,li,ki), rank, 'o', ...
                    'Color', FG, 'MarkerSize', 3, ...
                    'MarkerFaceColor', FG);
            end
        end
    end

    % Baseline vertical line
    xl = xline(ax, Y0, '--', 'Color', C_BL, 'LineWidth', 1.2);
    xl.Label = sprintf('Base\n%.3g', Y0);
    xl.LabelVerticalAlignment = 'bottom';
    xl.FontSize  = 7;
    xl.LabelColor = C_BL;

    % Axis labels
    yticks(ax, 1:n_params);
    yticklabels(ax, param_labels(order));
    xlabel(ax, sprintf('%s (%s = better)', kpp_names{ki}, better_dir{ki}), ...
        'Color', FG, 'FontSize', 9);
    title(ax, kpp_names{ki}, 'Color', FG, 'FontWeight','bold', 'FontSize',11);
    ylim(ax, [0.4, n_params + 0.6]);

    % Auto-scale x with a small margin
    all_vals = kpp_means(:,:,ki);
    x_lo = min(all_vals(:));
    x_hi = max(all_vals(:));
    margin = max((x_hi - x_lo) * 0.08, 1e-4);
    xlim(ax, [x_lo - margin, x_hi + margin]);
end

% Legend in the 6th (empty) cell
ax_leg = subplot(2, 3, 6);
set(ax_leg,'Color',BG,'Visible','off');
patch(ax_leg,[0 1 1 0],[0.7 0.7 0.8 0.8], C_LO,'EdgeColor','none','FaceAlpha',0.85);
patch(ax_leg,[0 1 1 0],[0.5 0.5 0.6 0.6], C_HI,'EdgeColor','none','FaceAlpha',0.85);
plot(ax_leg,0.5,0.35,'o','Color',C_BL,'MarkerSize',6);
text(ax_leg,1.1,0.75,'Decreases KPP value','Color',FG,'FontSize',9);
text(ax_leg,1.1,0.55,'Increases KPP value','Color',FG,'FontSize',9);
text(ax_leg,1.1,0.35,'Level sample','Color',FG,'FontSize',9);
text(ax_leg,1.1,0.15,'— Baseline','Color',C_BL,'FontSize',9);
xlim(ax_leg,[0 6]); ylim(ax_leg,[0 1]);

sgtitle(fig, 'OAT Sensitivity Analysis — ACMSCS Monte Carlo Simulation', ...
    'Color', FG, 'FontSize', 13, 'FontWeight','bold');
end
