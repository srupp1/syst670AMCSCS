function [state, encounters, trips, perception, enc_chk] = stepSimulation(state, env, cfg, t)
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
%
% Optional fifth output enc_chk: struct with n_ped_checked / n_veh_checked
% (total shuttle–agent pairs evaluated within detection radius this step).

state = updatePedestrians(state, env, cfg);
state = updateVehicles(state, env, cfg);
[state, trips] = updateShuttles(state, env, cfg, t);
[encounters, enc_chk] = detectConflicts(state, env, cfg, t);

perception = computePerception(state, env, cfg, t);
end
