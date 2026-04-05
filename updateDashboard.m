function dash = updateDashboard(dash, state, env, cfg, rep, step, elapsed, ...
                                enc_count, trip_count, kpp_running)
% updateDashboard  Refresh all live dashboard elements.
%
% kpp_running (optional) – struct with fields PCR, IVCR, ATD, SAA_recall, UTI
%                          containing running mean values from completed reps.

%% Shuttle positions
sx = [state.shuttles.x];
sy = [state.shuttles.y];
set(dash.h_sh, 'XData', sx, 'YData', sy);

%% Pedestrian positions
if ~isempty(state.peds)
    set(dash.h_pd, 'XData', [state.peds.x], 'YData', [state.peds.y]);
else
    set(dash.h_pd, 'XData', NaN, 'YData', NaN);
end

%% Vehicle positions
if ~isempty(state.vehs)
    set(dash.h_vh, 'XData', [state.vehs.x], 'YData', [state.vehs.y]);
else
    set(dash.h_vh, 'XData', NaN, 'YData', NaN);
end

%% Stats panel
t_sim  = cfg.t_start + (step - 1) * cfg.dt;
h_sim  = floor(t_sim / 3600);
m_sim  = floor(mod(t_sim, 3600) / 60);
frac   = (rep - 1 + step / cfg.n_steps) / cfg.n_replications;
eta    = elapsed / max(frac, 1e-6) * (1 - frac);

vals = { sprintf('%d / %d   (ETA %.0f s)', rep, cfg.n_replications, eta) ;
         sprintf('%d / %d',                step, cfg.n_steps)             ;
         sprintf('%02d:%02d',              h_sim, m_sim)                   ;
         sprintf('%.3f',                   state.weather)                  ;
         sprintf('%d',                     numel(state.peds))              ;
         sprintf('%d',                     numel(state.vehs))              ;
         sprintf('%d',                     enc_count)                      ;
         sprintf('%d',                     trip_count)                     };

for k = 1:numel(vals)
    dash.h_sv(k).String = vals{k};
end

%% KPP bars
if nargin >= 10 && ~isempty(kpp_running)
    fields     = {'PCR','IVCR','ATD','SAA_recall','UTI'};
    thresholds = [cfg.kpp.pcr_max, cfg.kpp.ivcr_max, cfg.kpp.atd_max, ...
                  cfg.kpp.saa_min, cfg.kpp.uti_min];
    directions = {'le','le','le','ge','ge'};

    norm_v = zeros(1, dash.n_kpp);
    colors = zeros(dash.n_kpp, 3);

    for k = 1:dash.n_kpp
        f  = fields{k};
        th = thresholds(k);
        if isfield(kpp_running, f) && ~isnan(kpp_running.(f))
            v = kpp_running.(f);
            if strcmp(directions{k}, 'le')
                norm_v(k) = min(1.5, v / max(th, 1e-9));
                passing   = v <= th;
            else
                norm_v(k) = min(1.5, th / max(v, 1e-9));
                passing   = v >= th;
            end
            if passing
                colors(k,:) = [0.18 0.72 0.35];   % green
            else
                colors(k,:) = [0.82 0.22 0.22];   % red
            end
            dash.h_bt(k).String = sprintf('%.4f', v);
            dash.h_bt(k).Position(1) = min(norm_v(k) + 0.04, 1.52);
        else
            norm_v(k)  = 0;
            colors(k,:)= [0.28 0.28 0.42];
            dash.h_bt(k).String = 'waiting...';
        end
    end

    dash.h_bar.XData  = norm_v;
    dash.h_bar.CData  = colors;
end

%% Progress bar
prog = max(1e-4, (rep - 1 + step / cfg.n_steps) / cfg.n_replications);
dash.h_pfill.Position(3) = prog;
dash.h_ptxt.String = sprintf('Rep %d / %d   |   Step %d / %d   |   %.1f s elapsed', ...
    rep, cfg.n_replications, step, cfg.n_steps, elapsed);

drawnow limitrate;
end
