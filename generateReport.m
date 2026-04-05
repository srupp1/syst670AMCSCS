function generateReport(kpps, cfg, out_file)
% generateReport  Print KPP summary to console and write CSV report.
%                 (SIM-RPT-001, SIM-EIF-002)
%
% Usage:  generateReport(kpps, cfg)            - auto filename
%         generateReport(kpps, cfg, 'out.csv') - explicit filename

if nargin < 3
    out_file = sprintf('acmscs_results_%s.csv', datestr(now,'yyyymmdd_HHMMSS'));
end

pass_str = @(r) ternary(r.pass, 'PASS', 'FAIL');

%% Console output
fprintf('\n======== ACMSCS KPP Verification Results ========\n');
fprintf('Replications: %d  |  Sim day: %02.0f:00 – %02.0f:00\n\n', ...
    cfg.n_replications, cfg.t_start/3600, cfg.t_end/3600);

fprintf('%-28s %8s %8s %8s %8s %6s\n', 'KPP', 'Mean', 'CI95-Lo', 'CI95-Hi', 'Thresh', 'Result');
fprintf('%s\n', repmat('-',1,72));
printRow('PCR (conflicts/ped-enc)',    kpps.PCR,       pass_str(kpps.PCR));
printRow('IVCR (conflicts/veh-enc)',   kpps.IVCR,      pass_str(kpps.IVCR));
printRow('ATD (%% delay)',             kpps.ATD,       pass_str(kpps.ATD));
printRow('SAA Recall',                 kpps.SAA_recall, pass_str(kpps.SAA_recall));
printRow('SAA Pred Error [m]',         kpps.SAA_pred_err, '(info)');
printRow('SAA Latency [s]',            kpps.SAA_latency,  '(info)');
printRow('UTI',                        kpps.UTI,       pass_str(kpps.UTI));
fprintf('%s\n', repmat('-',1,72));

all_pass = kpps.PCR.pass && kpps.IVCR.pass && kpps.ATD.pass && ...
           kpps.SAA_recall.pass && kpps.UTI.pass;
fprintf('Overall: %s\n\n', ternary(all_pass,'ALL KPPs PASS','ONE OR MORE KPPs FAIL'));

%% CSV output (SIM-CS-005)
fid = fopen(out_file, 'w');
if fid < 0
    warning('Could not write report to %s', out_file);
    return
end

fprintf(fid, 'KPP,Mean,Std,CI95_Lo,CI95_Hi,Threshold,Pass\n');
writeCSVRow(fid, 'PCR',          kpps.PCR);
writeCSVRow(fid, 'IVCR',         kpps.IVCR);
writeCSVRow(fid, 'ATD_pct',      kpps.ATD);
writeCSVRow(fid, 'SAA_recall',   kpps.SAA_recall);
writeCSVRow(fid, 'SAA_pred_err', kpps.SAA_pred_err);
writeCSVRow(fid, 'SAA_latency',  kpps.SAA_latency);
writeCSVRow(fid, 'UTI',          kpps.UTI);
fprintf(fid, '\nReplications,%d\n', cfg.n_replications);
fprintf(fid, 'Seed,%d\n', cfg.base_seed);
fclose(fid);
fprintf('Report saved → %s\n', out_file);
end

function printRow(label, r, result_str)
    fprintf('%-28s %8.4f %8.4f %8.4f %8.4f %6s\n', ...
        label, r.mean, r.ci95_lo, r.ci95_hi, r.threshold, result_str);
end

function writeCSVRow(fid, name, r)
    fprintf(fid, '%s,%.6f,%.6f,%.6f,%.6f,%.6f,%d\n', ...
        name, r.mean, r.std, r.ci95_lo, r.ci95_hi, r.threshold, r.pass);
end

function s = ternary(cond, a, b)
    if cond; s = a; else; s = b; end
end
