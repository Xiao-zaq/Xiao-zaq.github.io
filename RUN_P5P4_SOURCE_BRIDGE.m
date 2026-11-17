%% P5-P4 V1 — formal SF24 saved-flow source bridge ONLY.
% MATLAB R2023a. No production DNL/DUE/market or 135-case recomputation.
dbclear all;
restoredefaultpath;
clear functions;
rehash;
repo=fileparts(mfilename('fullpath'));
addpath(fullfile(repo,'matlab'),'-begin');
ws='C:\Users\Xiao\Desktop\Four Paper\CODE2\P4_V173_CODE2_WORKSPACE_20261111';
runDir=p5p4_formal_source_bridge(ws);
p5p4_independent_accept(runDir);
disp(['P5P4 source bridge complete: ' runDir]);