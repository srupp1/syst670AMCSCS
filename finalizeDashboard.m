function finalizeDashboard(dash, kpps, cfg)
% finalizeDashboard  Update dashboard with final verified KPP results.

fields     = {'PCR','IVCR','ATD','SAA_recall','UTI'};
thresholds = [cfg.kpp.pcr_max, cfg.kpp.ivcr_max, cfg.kpp.atd_max, ...
              cfg.kpp.saa_min, cfg.kpp.uti_min];
directions = {'le','le','le','ge','ge'};

norm_v = zeros(1, dash.n_kpp);
colors = zeros(dash.n_kpp, 3);

for k = 1:dash.n_kpp
    r  = kpps.(fields{k});
    th = thresholds(k);

    if strcmp(directions{k}, 'le')
        norm_v(k) = min(1.5, r.mean / max(th, 1e-9));
    else
        norm_v(k) = min(1.5, th / max(r.mean, 1e-9));
    end

    if r.pass
        colors(k,:) = [0.18 0.72 0.35];
        status = 'PASS';
    else
        colors(k,:) = [0.82 0.22 0.22];
        status = 'FAIL';
    end

    dash.h_bt(k).String = sprintf('%.4f  [%.4f, %.4f]  %s', ...
        r.mean, r.ci95_lo, r.ci95_hi, status);
    dash.h_bt(k).Position(1) = min(norm_v(k) + 0.04, 1.52);
end

dash.h_bar.XData = norm_v;
dash.h_bar.CData = colors;

title(dash.ax_kpp, 'Final KPP Results  (mean  [95% CI]  pass/fail)', ...
    'Color',[0.90 0.90 0.95],'FontSize',10,'FontWeight','bold');

% Progress bar: complete
dash.h_pfill.Position(3) = 1.0;

all_pass = kpps.PCR.pass && kpps.IVCR.pass && kpps.ATD.pass && ...
           kpps.SAA_recall.pass && kpps.UTI.pass;

if all_pass
    dash.h_pfill.FaceColor = [0.18 0.78 0.40];
    msg = sprintf('COMPLETE — %d replications — ALL KPPs PASS', cfg.n_replications);
    dash.h_ptxt.Color = [0.30 1.00 0.50];
else
    dash.h_pfill.FaceColor = [0.80 0.22 0.22];
    msg = sprintf('COMPLETE — %d replications — ONE OR MORE KPPs FAIL', cfg.n_replications);
    dash.h_ptxt.Color = [1.00 0.40 0.40];
end
dash.h_ptxt.String = msg;

drawnow;
end
