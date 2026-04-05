function cfg = getDefaultConfig()
% getDefaultConfig  Return default ACMSCS simulation configuration.
% Override fields before passing to main, e.g.: cfg.n_replications = 1000;

% Monte Carlo
cfg.n_replications  = 100;      % Replications (use 1000 for full run)
cfg.base_seed       = 42;       % Base RNG seed (SIM-CAP-011)

% Time
cfg.t_start   = 7 * 3600;      % 07:00 [s]
cfg.t_end     = 22 * 3600;     % 22:00 [s]
cfg.dt        = 10;             % Time step [s]
cfg.n_steps   = (cfg.t_end - cfg.t_start) / cfg.dt;  % 5400 steps/day

% Fleet (SIM-CAP-001, SIM-CAP-004)
cfg.n_shuttles        = 3;
cfg.speed_mean        = 4.0;    % Nominal speed [m/s]  (~14.4 km/h)
cfg.speed_std         = 0.3;    % Speed std dev [m/s]
cfg.max_decel         = 2.0;    % Max deceleration [m/s^2]
cfg.dwell_time        = 30;     % Stop dwell time [s]

% Pedestrians (SIM-CAP-002) — Poisson arrivals
cfg.ped_rate_base     = 0.04;   % Arrival rate at large crossing [ped/s]
cfg.ped_speed_mean    = 1.4;    % Walking speed [m/s]
cfg.ped_speed_std     = 0.2;
cfg.ped_cross_time    = 8;      % Time to cross road [s]
cfg.ped_detect_radius = 8.0;    % Conflict check distance [m]

% Background vehicles (SIM-CAP-003)
cfg.veh_rate          = 1/300;  % Vehicle arrival rate [veh/s] on loop
cfg.veh_speed_mean    = 5.0;    % [m/s] (~18 km/h)
cfg.veh_speed_std     = 0.5;
cfg.veh_detect_radius = 20.0;   % Following-distance conflict threshold [m]

% Weather (normal, 1 = fair, lower = worse)
cfg.weather_mean      = 1.0;
cfg.weather_std       = 0.08;

% Safety thresholds (SIM-RUN-002)
cfg.ttc_high    = 1.5;          % TTC < this → high severity [s]
cfg.ttc_med     = 3.0;          % TTC < this → medium severity [s]
cfg.pet_thresh  = 1.5;          % PET threshold [s]
cfg.min_sep_ped = 3.0;          % Min acceptable separation ped [m]
cfg.min_sep_veh = 8.0;          % Min acceptable separation veh [m]

% Perception model (SIM-CAP-008)
cfg.detect_prob       = 0.95;   % Detection probability per agent per step
cfg.pos_noise_std     = 0.5;    % Position measurement noise [m]
cfg.pred_horizon      = 3.0;    % Prediction horizon [s]
cfg.latency_mean      = 0.050;  % Mean perception latency [s]
cfg.latency_std       = 0.010;

% KPP pass/fail thresholds (SIM-KPP-001)
cfg.kpp.pcr_max     = 0.10;     % Max pedestrian conflict rate [conflicts/ped-crossing]
cfg.kpp.ivcr_max    = 0.05;     % Max inter-vehicle conflict rate [conflicts/veh-encounter]
cfg.kpp.atd_max     = 15.0;     % Max average trip delay [%]
cfg.kpp.saa_min     = 0.95;     % Min detection recall
cfg.kpp.uti_min     = 0.75;     % Min user trust index [0-1]
end
