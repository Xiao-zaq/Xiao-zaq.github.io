function p4r_plot_saved(source,out)
% Actual preserved mapping figures only; no synthetic replacement values.
figDir=fullfile(out,'Figures');mkdir(figDir);
D=readtable(fullfile(source,'P5P3_DEPARTURE_TIME_CLASS_TOTAL.csv'));
f=figure('Visible','off','Color','w');hold on;
for c=1:2,sel=D.SOCClassID==c;plot(D.DepartureTimeIndex(sel)-1,D.MassVeh(sel),'LineWidth',1.5);end
xlabel('Departure minutes from 08:00');ylabel('Mass (veh / departure bin)');legend('Low SOC','High SOC');
title('Preserved departure flow mapping');writeFigure(f,'S01_Departure');
O=readtable(fullfile(source,'P5P3_OD_CLASS_MASS.csv'));Y=zeros(12,2);
for k=1:height(O),Y(O.ODIndex(k),O.SOCClassID(k))=O.MappedVeh(k);end
f=figure('Visible','off','Color','w');bar(Y,'stacked');xlabel('OD index');ylabel('Mass (veh)');legend('Low SOC','High SOC');title('Preserved OD mass');writeFigure(f,'S02_OD_Mass');
S=readtable(fullfile(source,'P5P3_STATION_CLASS_PATH_ASSIGNMENT.csv'));Y=zeros(4,2);
for k=1:height(S),Y(S.StationID(k),S.SOCClassID(k))=S.DeparturePathAssignedVeh(k);end
f=figure('Visible','off','Color','w');bar(Y,'stacked');xlabel('Station in intended departure path');ylabel('Mass (veh)');legend('Low SOC','High SOC');title('Path-assigned mass, not realized station arrivals');writeFigure(f,'S03_Station_Path_Mass');
L=readtable(fullfile(source,'P5P3_LINK_CAPACITY_AND_PATH_INCIDENCE.csv'),'TextType','string');ix=L.Kind=="ROAD"|L.Kind=="WCL";
f=figure('Visible','off','Color','w');plot(L.LinkID(ix),L.DeparturePathIncidenceVeh(ix),'LineWidth',1.2);hold on;plot(L.LinkID(ix),L.SavedIntegratedRoadVolumeVeh(ix),'.');
xlabel('Link ID');ylabel('Full-horizon incidence (veh)');legend('Path incidence','Saved integrated volume');title('Integrated volume identity, no entry-clock inference');writeFigure(f,'S04_Link_Incidence');
    function writeFigure(fig,name)
        exportgraphics(fig,fullfile(figDir,[name '.png']),'Resolution',300);
        savefig(fig,fullfile(figDir,[name '.fig']));close(fig);
    end
end
