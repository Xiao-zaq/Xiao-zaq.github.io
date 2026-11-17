%% Verify/show existing GitHub reference outputs; do not recalculate.
dbclear all;
restoredefaultpath;
clear functions;
rehash;
repo=fileparts(mfilename('fullpath'));
addpath(repo,'-begin');
START_P4_RESEARCH_V1('review');
disp('Reference outputs are component results, NOT formal SF24 DNL.');