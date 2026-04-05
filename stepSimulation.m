function [state, encounters, trips, perception] = stepSimulation(state, env, cfg, t)
% stepSimulation  Advance simulation by one time step (cfg.dt seconds).
%
% Sequence (SIM-RUN-001, SIM-RUN-002):
%   1. Generate pedestrian arrivals
%   2. Generate background vehicle arrivals
%   3. Update shuttle positions; collect completed trips
%   4. Update pedestrian positions
%   5. Update vehicle positions
%   6. Conflict detection (TTC, PET, separation)
%   7. Perception model

state = updatePedestrians(state, env, cfg);
state = updateVehicles(state, env, cfg);
[state, trips] = updateShuttles(state, env, cfg, t);
encounters     = detectConflicts(state, cfg, t);
perception     = computePerception(state, cfg, t);
end
