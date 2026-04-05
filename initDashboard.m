function dash = initDashboard(env, cfg)
% initDashboard  Create the live simulation dashboard figure.
% Returns a struct of handles used by updateDashboard / finalizeDashboard.

bg        = [0.10 0.10 0.16];
panel_bg  = [0.13 0.13 0.20];
txt_col   = [0.90 0.90 0.95];
grid_col  = [0.25 0.25 0.35];

fig = figure('Name','ACMSCS Simulation Dashboard', ...
    'Position',[30 30 1380 700], ...
    'Color',bg, 'NumberTitle','off', 'MenuBar','none', ...
    'Resize','on');

%% ── Left panel: campus map ──────────────────────────────────────────────
ax_map = axes(fig, 'Position',[0.02 0.09 0.50 0.87], ...
    'Color',panel_bg, 'XColor',[0.40 0.40 0.55], 'YColor',[0.40 0.40 0.55], ...
    'GridColor',grid_col, 'GridAlpha',0.35, 'FontSize',8);
hold(ax_map,'on');  grid(ax_map,'on');  axis(ax_map,'equal');
title(ax_map,'UMBC Campus — Live Shuttle Tracking', ...
    'Color',txt_col,'FontSize',11,'FontWeight','bold');
xlabel(ax_map,'X [m]','Color',txt_col,'FontSize',8);
ylabel(ax_map,'Y [m]','Color',txt_col,'FontSize',8);

% All graph edges (campus roads)
for e = 1:env.n_edges
    s = env.src_idx(e);  t = env.tgt_idx(e);
    plot(ax_map, env.pos([s,t],1), env.pos([s,t],2), ...
        '-','Color',[0.28 0.28 0.42],'LineWidth',1.5);
end

% Shuttle route path (highlighted)
for e = 1:env.n_seg
    n1 = env.node_seq(e);
    n2 = env.node_seq(mod(e, env.n_seg)+1);
    plot(ax_map, env.pos([n1,n2],1), env.pos([n1,n2],2), ...
        '-','Color',[0.25 0.50 0.85 0.65],'LineWidth',2.8);
end

% All nodes
scatter(ax_map, env.pos(:,1), env.pos(:,2), 30, ...
    [0.55 0.55 0.72],'filled','MarkerEdgeColor','none');

% Route stop nodes (larger, labelled)
for i = 1:env.n_legs
    nd = env.stop_nodes(i);
    scatter(ax_map, env.pos(nd,1), env.pos(nd,2), 70, ...
        [0.40 0.72 1.00],'filled','^','MarkerEdgeColor',[0.75 0.90 1.00],'LineWidth',1);
    text(ax_map, env.pos(nd,1)+5, env.pos(nd,2)+5, env.names{nd}, ...
        'Color',[0.70 0.85 1.00],'FontSize',7,'FontWeight','bold');
end

% Live agent markers (updated each frame)
h_sh = scatter(ax_map, nan(1,cfg.n_shuttles), nan(1,cfg.n_shuttles), ...
    180, repmat([0.00 1.00 0.88],cfg.n_shuttles,1), 'filled', 's', ...
    'MarkerEdgeColor',[1 1 1],'LineWidth',1.5,'DisplayName','Shuttle');
h_pd = scatter(ax_map, NaN, NaN, 28, [1.00 0.92 0.20],'filled','o', ...
    'MarkerEdgeColor','none','DisplayName','Pedestrian');
h_vh = scatter(ax_map, NaN, NaN, 32, [1.00 0.55 0.12],'filled','d', ...
    'MarkerEdgeColor','none','DisplayName','Vehicle');

legend(ax_map, [h_sh, h_pd, h_vh], {'Shuttle','Pedestrian','Vehicle'}, ...
    'TextColor',txt_col,'Color',panel_bg,'EdgeColor',grid_col, ...
    'FontSize',8,'Location','southeast');

%% ── Top-right panel: status ─────────────────────────────────────────────
ax_st = axes(fig,'Position',[0.55 0.53 0.43 0.43], ...
    'Color',panel_bg,'XColor','none','YColor','none','XTick',[],'YTick',[]);
axis(ax_st,'off');
xlim(ax_st,[0 1]);  ylim(ax_st,[0 1]);
text(ax_st,0.50,0.97,'Simulation Status','Color',txt_col, ...
    'FontSize',11,'FontWeight','bold','HorizontalAlignment','center', ...
    'Units','normalized');

labels = {'Replication:','Time step:','Sim time:','Weather:', ...
          'Pedestrians:','Vehicles:','Encounters:','Trips:'};
h_sv = gobjects(numel(labels),1);
row_h = 0.88;
for k = 1:numel(labels)
    text(ax_st, 0.04, row_h, labels{k}, ...
        'Color',[0.60 0.62 0.75],'FontSize',9,'Units','normalized');
    h_sv(k) = text(ax_st, 0.55, row_h, '—', ...
        'Color',txt_col,'FontSize',9,'FontWeight','bold','Units','normalized');
    row_h = row_h - 0.115;
end

%% ── Bottom-right panel: KPP bars ────────────────────────────────────────
ax_kpp = axes(fig,'Position',[0.55 0.09 0.43 0.40], ...
    'Color',panel_bg,'XColor',[0.45 0.45 0.58],'YColor',[0.45 0.45 0.58], ...
    'GridColor',grid_col,'GridAlpha',0.35,'FontSize',8);
hold(ax_kpp,'on');  grid(ax_kpp,'on');
title(ax_kpp,'KPP Estimates (running mean across completed replications)', ...
    'Color',txt_col,'FontSize',9,'FontWeight','bold');
xlabel(ax_kpp,'Normalised ratio  (≤ 1.0 = within threshold)', ...
    'Color',txt_col,'FontSize',8);

kpp_names = {'PCR','IVCR','ATD','SAA recall','UTI'};
n_kpp = numel(kpp_names);

h_bar = barh(ax_kpp, 1:n_kpp, zeros(1,n_kpp), 0.55, ...
    'FaceColor','flat','EdgeColor','none');
h_bar.CData = repmat([0.28 0.45 0.72], n_kpp, 1);

% Threshold reference line
xl = xline(ax_kpp, 1.0,'--','Color',[1.00 0.38 0.38],'LineWidth',1.8, ...
    'Label','Threshold','FontSize',8);
xl.Color = [1.00 0.38 0.38];

xlim(ax_kpp,[0 1.6]);
ylim(ax_kpp,[0.3 n_kpp+0.7]);
yticks(ax_kpp, 1:n_kpp);
yticklabels(ax_kpp, kpp_names);
ax_kpp.YAxis.TickLabelColor = txt_col;
ax_kpp.XAxis.TickLabelColor = [0.55 0.55 0.68];

h_bt = gobjects(n_kpp,1);
for k = 1:n_kpp
    h_bt(k) = text(ax_kpp, 0.03, k, '—', ...
        'Color',txt_col,'FontSize',8,'FontWeight','bold', ...
        'VerticalAlignment','middle');
end

%% ── Progress strip (bottom) ─────────────────────────────────────────────
ax_pr = axes(fig,'Position',[0.02 0.01 0.96 0.055], ...
    'Color',bg,'XColor','none','YColor','none','XTick',[],'YTick',[]);
axis(ax_pr,'off');
xlim(ax_pr,[0 1]);  ylim(ax_pr,[0 1]);
rectangle(ax_pr,'Position',[0 0.05 1 0.90], ...
    'FaceColor',[0.14 0.14 0.22],'EdgeColor','none');
h_pfill = rectangle(ax_pr,'Position',[0 0.05 1e-4 0.90], ...
    'FaceColor',[0.18 0.55 0.90],'EdgeColor','none');
h_ptxt = text(ax_pr,0.5,0.5,'Initialising...', ...
    'Color',txt_col,'FontSize',9,'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle');

%% Pack
dash.fig     = fig;
dash.ax_map  = ax_map;
dash.h_sh    = h_sh;
dash.h_pd    = h_pd;
dash.h_vh    = h_vh;
dash.ax_kpp  = ax_kpp;
dash.h_bar   = h_bar;
dash.h_bt    = h_bt;
dash.h_sv    = h_sv;
dash.h_pfill = h_pfill;
dash.h_ptxt  = h_ptxt;
dash.n_kpp   = n_kpp;

drawnow;
end
