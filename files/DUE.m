%% DUE.m - 优化后的 DUE 模型代码

clc;
clear;

global NET FLOW PARA iteration

% 1) 参数和网络初始化
initialize_parameters();
read_network();  % 读网络与数据

% 2) 初始最短路（基于初始 FFT 行程时间）
for oi = 1:NET.originnum
    for c = 1:PARA.numClasses
        shortestpathfun(oi, 1, c);  % 使用 Dijkstra 计算最短路径
    end
end

% 3) 初始化路径流量（只给每个OD的第一条路径均匀配流）
[FLOW.pathFlow, ~] = initialize_flow();
iteration = 0;
disp('--- Initialization is finished ---');

tic;

% ===== 首次 DNL：使用“新一轮”的 pathRemainingCharge0 =====
basePathRemainingCharge = build_base_remaining_charge(NET, PARA);
NET.linkTrlTime = update_FLOW(FLOW.pathFlow, basePathRemainingCharge);
NET.pathTC = get_travel_cost(NET.linkTrlTime);

% 4) 迭代求解 DUE
while true
    iteration = iteration + 1;
    fcratio = 1e2;

    % 内层：route-swapping 收敛
    while fcratio > PARA.error
        % 用当前路径成本做一次 route-swapping
        fcratio = gap_func_and_distribute_flow_pattern(iteration, NET.pathTC);

        % 对“更新后的 FLOW.pathFlow”再做一次 DNL
        NET.linkTrlTime = update_FLOW(FLOW.pathFlow, basePathRemainingCharge);
        NET.pathTC = get_travel_cost(NET.linkTrlTime);
    end

    % 外层：新路径探索
    NET.newpathindicator = 0;
    for oi = 1:NET.originnum
        for c = 1:PARA.numClasses
            for ki = 1:PARA.numSubInterval
                shortestpathfun(oi, ki, c);  % 使用 Dijkstra 更新路径
            end
        end
    end

    % 收敛判定与误差阈值调整
    if ~NET.newpathindicator
        % 没有新路径
        if PARA.error == PARA.minerror
            % 误差已到最小，停止迭代
            break;
        else
            % 否则进一步收紧误差阈值，进行下一轮外层迭代
            PARA.error = max(PARA.errorscale * PARA.error, PARA.minerror);
        end
    else
        % 有新路径：用新的路径集重新 DNL + 成本
        NET.linkTrlTime = update_FLOW(FLOW.pathFlow, basePathRemainingCharge);
        NET.pathTC = get_travel_cost(NET.linkTrlTime);

        % 为了加快收敛，适当放宽误差阈值
        PARA.error = min(PARA.error / PARA.errorscale, PARA.maxerror);
    end
end

toc;

% 5) 画图 & 保存结果
FigureFlowfun();
FigureCostfun();

disp('========== DUE 计算完成 ==========');
disp(['总迭代次数: ', num2str(iteration)]);
save('DUE_results.mat', 'NET', 'FLOW', 'PARA', 'iteration');
disp('结果已保存到 DUE_results.mat');

%% 1) 初始化参数
function initialize_parameters()
    global PARA
    PARA.ITUnit     = 1;              % 分钟/步
    PARA.dt_hr      = PARA.ITUnit/60; % 小时/步
    PARA.start      = 8;              % 小时
    PARA.flowInEnd  = 10;             % 小时
    PARA.dayEnd     = 18;             % 小时

    PARA.timeunit   = 6.4/60*PARA.ITUnit;   % 时间成本/步
    PARA.earlyunit  = 3.9/60*PARA.ITUnit;   % 早到惩罚/步
    PARA.lateunit   = 15.21/60*PARA.ITUnit; % 晚到惩罚/步
    PARA.delta      = 6/PARA.ITUnit;        % 偏好出发偏差（步）

    PARA.workinterval    = (PARA.flowInEnd - PARA.start)*60/PARA.ITUnit;
    PARA.numInterval     = (PARA.dayEnd    - PARA.start)*60/PARA.ITUnit;
    PARA.numSubInterval  = ceil((PARA.flowInEnd - PARA.start)*60/PARA.ITUnit);

    PARA.minerror  = 1e-5;
    PARA.maxerror  = 1e-1;
    PARA.rho       = 1e-1;
    PARA.rhoBase   = 1000;
    PARA.error     = PARA.maxerror;
    PARA.errorscale= 1e-1;

    % 多类 EV
    PARA.userClassNames = {'低SOC EV','高SOC EV'};
    PARA.numClasses     = numel(PARA.userClassNames);
    PARA.SOCinitVec     = [0.2, 0.7];
    PARA.SOCtarget      = 1.0;
    PARA.BatteryCapacity_kWh = 60;
    PARA.chargeDemandPerClass = (PARA.SOCtarget - PARA.SOCinitVec) * PARA.BatteryCapacity_kWh;
    PARA.classShare     = [0.7, 0.3];  % 和为 1

    % 能量/价格/功率
    PARA.energyPerKm           = 0.02;  % kWh/km
    PARA.energyPricePerKWh     = 0.2;
    PARA.WCLpricePerKWh        = 2.0;
    PARA.stationPricePerKWh    = 1.3;
    PARA.WCLchargePower        = 75;   % kW
    PARA.stationChargerPower   = 90;   % kW
    PARA.eta                   = 0.8;  % WCL 排队放大系数

    PARA.debug = 0;
end

%% 2) 读取网络与需求数据
function read_network()
    global NET PARA FLOW

    % PATH 初始化
    NET.newpathindicator = 0;
    NET.numPath          = 0;
    NET.maxWidthPath     = 50;
    NET.maxnumPathperOd  = 10;

    % 读 OD 需求
    ODdemand0     = textread('ODdemand.txt');
    demand_type   = sortrows(ODdemand0);
    NET.numOdPair = size(demand_type,1);
    NET.maxnumPath= NET.numOdPair * NET.maxnumPathperOd;

    NET.flagInfo  = zeros(NET.maxnumPath, 2);
    NET.odPair    = -ones(NET.maxnumPath, NET.maxWidthPath);

    [c, d, ~]       = unique(demand_type(:,1));
    NET.origin      = c;
    NET.originindex = [d; NET.numOdPair+1];
    NET.originnum   = numel(c);
    NET.o           = demand_type(:,1);
    NET.d           = demand_type(:,2);

    NET.odPairFeature = zeros(NET.maxnumPath,1);
    for i = 1:NET.numOdPair
        range = (i-1)*NET.maxnumPathperOd + (1:NET.maxnumPathperOd);
        NET.odPairFeature(range) = demand_type(i,3);
    end
    NET.odDemand = demand_type(:,3);

    % 读网络
    Network0       = textread('networkset.txt');
    NET.linkAttr   = sortrows(Network0);  % 1 tail, 2 head, 3 cap, 4 length, 5 fft, 6 B, 7 power, 8 isWCL, 9 isStation, 10 stationCap
    NET.linkAttr(:,6) = NET.linkAttr(:,6)./ NET.linkAttr(:,6);
    NET.linkAttr(:,7) = NET.linkAttr(:,7)./ NET.linkAttr(:,7);

    NET.numLink = size(NET.linkAttr,1);
    [a,b,~]     = unique(NET.linkAttr(:,1));
    NET.uniquestartnode = a;
    NET.startindex      = [b; NET.numLink+1];
    NET.startnode       = NET.linkAttr(:,1);
    NET.endnode         = NET.linkAttr(:,2);

    % 单位化
    NET.linkAttr(:,3) = NET.linkAttr(:,3) * PARA.ITUnit;   % cap: veh/step
    NET.linkAttr(:,5) = NET.linkAttr(:,5) / PARA.ITUnit;   % fft: step
    NET.linkTrlTime   = NET.linkAttr(:,5) .* ones(NET.numLink, PARA.numInterval);

    % 充电相关标志（按输入列）
    NET.isWireless             = NET.linkAttr(:,8);   % 1=WCL
    NET.isStationLink          = NET.linkAttr(:,9);   % 1=站点虚拟入站链
    NET.stationChargerCapacity = NET.linkAttr(:,10);  % kWh/步 级别或等效容量（见 update_FLOW 的换算）

    % 其他存储
    NET.numNode   = max(max(NET.linkAttr(:,1:2)));
    NET.nodeToStartIdx = zeros(NET.numNode,1);
    NET.nodeToStartIdx(NET.uniquestartnode) = 1:numel(NET.uniquestartnode);
    NET.pathTT    = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    NET.pathTC    = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);

    FLOW.pathFlow            = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    FLOW.pathRemainingCharge = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    FLOW.pathSOC             = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    FLOW.pathSOC_e           = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);

    NET.linkChargeEnergy            = zeros(NET.numLink, PARA.numInterval);
    NET.linkChargeEnergy_byClass    = zeros(NET.numLink, PARA.numInterval, PARA.numClasses);
    NET.pathChargeEnergy            = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    NET.stationQueueTime            = zeros(NET.numLink, PARA.numSubInterval, PARA.numClasses);
    NET.stationQueueVehicles        = zeros(NET.numLink, PARA.numSubInterval, PARA.numClasses);

    if PARA.ITUnit < 0.2
        disp('You may get nice results, but also experience strange things');
    end
end

%%
function [pathFlow, pathRemainingCharge] = initialize_flow()
    global FLOW NET PARA

    pathFlow            = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    pathRemainingCharge = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);

    for i = 1:NET.numOdPair
        posPath = (i-1)*NET.maxnumPathperOd + 1;
        baseFlowPerTime = NET.odPairFeature(posPath) / PARA.numSubInterval;
        for c = 1:PARA.numClasses
            pathFlow(posPath, :, c) = baseFlowPerTime * PARA.classShare(c);
        end
    end

    for pi = 1:NET.maxnumPath
        for ki = 1:PARA.numSubInterval
            for c = 1:PARA.numClasses
                pathRemainingCharge(pi, ki, c) = PARA.chargeDemandPerClass(c);
            end
        end
    end

    FLOW.pathFlow            = pathFlow;
    FLOW.pathRemainingCharge = pathRemainingCharge;
end

%% 3) 更新链路流量
function linkTrlTime = update_FLOW(pathFlow, pathRemainingCharge)
    global NET PARA FLOW

    freeFTT   = 5;   % 自由流时间列
    capacity  = 3;   % 容量列

    eps_val   = 1e-6;
    freeFlowTimes = NET.linkAttr(:, freeFTT);
    freeFlowTimes(freeFlowTimes<=0) = eps_val;
    linkTrlTime = freeFlowTimes .* ones(NET.numLink, PARA.numInterval);
    linkLengthKm = NET.linkAttr(:,4);

    hasStation = isfield(NET,'isStationLink');
    if hasStation
        stationLinks = NET.isStationLink == 1;
        stationVehCap = NET.stationChargerCapacity ./ (PARA.dt_hr * PARA.stationChargerPower);
        stationVehCap = max(stationVehCap, ones(size(stationVehCap)));
    else
        stationLinks = false(NET.numLink,1);
        stationVehCap = zeros(NET.numLink,1);
    end
    linkCapacity = NET.linkAttr(:, capacity);
    if hasStation
        linkCapacity(stationLinks) = stationVehCap(stationLinks);
    end

    hasWireless = isfield(NET,'isWireless');
    if hasWireless
        wirelessLinks = NET.isWireless == 1;
    else
        wirelessLinks = false(NET.numLink,1);
    end

    % 预分配
    linkInFlow_byClass = zeros(NET.numLink, PARA.numInterval, PARA.numClasses);
    pathAccuInFlow     = zeros(NET.maxnumPath, PARA.numInterval, PARA.numClasses);
    pathAccuOutFlow    = zeros(NET.maxnumPath, PARA.numInterval, PARA.numClasses);
    pathoutflow_pk     = zeros(NET.maxnumPath, PARA.numInterval, PARA.numClasses);
    linkInFlow         = zeros(NET.numLink, PARA.numInterval);
    linkQueue          = zeros(NET.numLink, PARA.numInterval);

    % 记录 WCL 充电能量（单车充电量 × 车辆数）
    linkChargeEnergy_byClass = zeros(NET.numLink, PARA.numInterval, PARA.numClasses);
    linkChargeEnergy         = zeros(NET.numLink, PARA.numInterval);

    % cumulativeflow: [flow | pi | origin_departure | class | soc_e | rem_kWh | path_pos]
    blkRows        = 400;
    numCFfields    = 7;
    cumulativeflow = zeros(blkRows, numCFfields*NET.numLink);
    cumulativepnum = zeros(1, NET.numLink);
    maxsumoutflow  = zeros(NET.numOdPair, 1);

    % 路径×链路×类 的即时注入缓存
    pathlinkInFlow = zeros(NET.maxnumPath, NET.numLink, PARA.numClasses);
    validPaths = find(NET.flagInfo(:,2)>0);
    firstLinkPerPath = zeros(NET.maxnumPath,1);
    if ~isempty(validPaths)
        firstLinkPerPath(validPaths) = NET.odPair(validPaths,1);
    end

    for ki = 1:PARA.numInterval

        % 1) 注入（仅流入窗内）
        if ki <= PARA.numSubInterval && ~isempty(validPaths)
            for idx = 1:numel(validPaths)
                pi = validPaths(idx);
                firstLink = firstLinkPerPath(pi);
                for c = 1:PARA.numClasses
                    inj = 0;
                    if pi<=size(pathFlow,1) && ki<=size(pathFlow,2) && c<=size(pathFlow,3)
                        inj = pathFlow(pi,ki,c);
                    end
                    if inj>0 && firstLink>0
                        pathlinkInFlow(pi, firstLink, c) = pathlinkInFlow(pi, firstLink, c) + inj;
                    end

                    if ki==1
                        pathAccuInFlow(pi, ki, c) = inj;
                    else
                        pathAccuInFlow(pi, ki, c) = pathAccuInFlow(pi, ki-1, c) + inj;
                    end

                    % 初始化该批的 SOC_e 与固定“剩余充电需求”
                    if inj>0
                        base_demand = PARA.chargeDemandPerClass(c);
                        if pi<=size(pathRemainingCharge,1) && ki<=size(pathRemainingCharge,2) && c<=size(pathRemainingCharge,3)
                            rem_kWh = pathRemainingCharge(pi,ki,c);
                            if rem_kWh<=0, rem_kWh = base_demand; end
                        else
                            rem_kWh = base_demand;
                        end
                        init_soc  = PARA.SOCinitVec(c);

                        % 只更新对应切片，避免抹掉其他诊断数据
                        FLOW.pathSOC(pi, ki, c)             = init_soc;
                        FLOW.pathSOC_e(pi, ki, c)           = init_soc;
                        FLOW.pathRemainingCharge(pi, ki, c) = rem_kWh;
                    end
                end
            end
        end

        % 早停（所有 OD 的累计出流达到需求）
        if all(abs(maxsumoutflow(:) - NET.odDemand(:)) < 1e-6)
            break;
        end

        % 2) 链路 FIFO 传播
        for li = 1:NET.numLink
            if cumulativepnum(li) == 0, continue; end

            cap_li = linkCapacity(li);

            startki = cumulativeflow(1, li + 2*NET.numLink);
            if ki < startki + floor(freeFlowTimes(li)), continue; end

            if ki == startki + floor(freeFlowTimes(li))
                arrtime = startki + freeFlowTimes(li);
                actualcapacity = (floor(arrtime)+1 - arrtime)*cap_li;
            else
                actualcapacity = cap_li;
            end

            rowsIdx = find(cumulativeflow(1:cumulativepnum(li), li + 2*NET.numLink) == startki);
            if isempty(rowsIdx), continue; end
            sumrowj = sum(cumulativeflow(rowsIdx, li));

            % 本链路每车 WCL 电量（kWh/veh）
            perVeh_kwh = 0;
            if hasWireless && wirelessLinks(li)
                baseIdx    = max(1, min(ki, PARA.numInterval-1));  % 防溢
                % 用当前步的链路行程时间估算在链上的时长
                link_tt = linkTrlTime(li, baseIdx);
                if baseIdx+1 <= size(linkTrlTime,2)
                    % 轻微平滑
                    link_tt = 0.5*(link_tt + linkTrlTime(li, baseIdx+1));
                end
                perVeh_kwh = PARA.WCLchargePower * link_tt * PARA.dt_hr;
            end

            if sumrowj > actualcapacity
                denom = max(sumrowj, eps);
                for rr = 1:numel(rowsIdx)
                    rowi     = rowsIdx(rr);
                    pi       = cumulativeflow(rowi, li + NET.numLink);
                    recClass = cumulativeflow(rowi, li + 3*NET.numLink);
                    idx_li   = cumulativeflow(rowi, li + 6*NET.numLink);
                    if idx_li <= 0
                        idx_li = find(NET.odPair(pi,:)==li, 1, 'first');
                    end

                    moved = cumulativeflow(rowi, li)/denom * actualcapacity;

                    % --- 批次级更新（WCL 抵扣固定需求；站点置零；SOC_e 记账）---
                    [soc_after, rem_after] = update_batch_SOC(rowi, li, perVeh_kwh);

                    % --- 统计 WCL 能量（按类）---
                    if perVeh_kwh > 0 && moved > 0 && recClass>=1 && recClass<=PARA.numClasses
                        linkChargeEnergy_byClass(li, ki, recClass) = linkChargeEnergy_byClass(li, ki, recClass) + perVeh_kwh * moved;
                    end

                    if idx_li == NET.flagInfo(pi,2)
                        pathoutflow_pk(pi, ki, recClass) = pathoutflow_pk(pi, ki, recClass) + moved;
                    else
                        nextli = NET.odPair(pi, idx_li+1);
                        pathlinkInFlow(pi, nextli, recClass) = pathlinkInFlow(pi, nextli, recClass) + moved;
                    end
                    cumulativeflow(rowi, li) = cumulativeflow(rowi, li) - moved;
                end

            else
                % 可能多批次放行
                while true
                    if ki < startki + floor(freeFlowTimes(li)) || sum(cumulativeflow(1:cumulativepnum(li), li))==0
                        break;
                    end
                    rowsIdx = find(cumulativeflow(1:cumulativepnum(li), li + 2*NET.numLink) == startki);
                    if isempty(rowsIdx), break; end
                    sumrowj = sum(cumulativeflow(rowsIdx, li));

                    if ki == startki + floor(freeFlowTimes(li))
                        arrtime   = startki + freeFlowTimes(li);
                        windowCap = (floor(arrtime)+1 - arrtime)*cap_li;
                    else
                        windowCap = inf;
                    end
                    availCap = min(actualcapacity, windowCap);

                    if sumrowj <= availCap
                        totalBatch = sumrowj;
                        denom      = max(sum(cumulativeflow(rowsIdx, li)), eps);
                        for rr = 1:numel(rowsIdx)
                            rowi     = rowsIdx(rr);
                            pi       = cumulativeflow(rowi, li + NET.numLink);
                            recClass = cumulativeflow(rowi, li + 3*NET.numLink);
                            idx_li   = cumulativeflow(rowi, li + 6*NET.numLink);
                            if idx_li <= 0
                                idx_li = find(NET.odPair(pi,:)==li, 1, 'first');
                            end

                            % 更新批次 SOC/剩余
                            [soc_after, rem_after] = update_batch_SOC(rowi, li, perVeh_kwh);

                            % 统计 WCL 能量
                            moved = cumulativeflow(rowi, li)/denom * totalBatch;
                            if perVeh_kwh > 0 && moved > 0 && recClass>=1 && recClass<=PARA.numClasses
                                linkChargeEnergy_byClass(li, ki, recClass) = linkChargeEnergy_byClass(li, ki, recClass) + perVeh_kwh * moved;
                            end

                            if idx_li == NET.flagInfo(pi,2)
                                pathoutflow_pk(pi, ki, recClass) = pathoutflow_pk(pi, ki, recClass) + moved;
                            else
                                nextli = NET.odPair(pi, idx_li+1);
                                pathlinkInFlow(pi, nextli, recClass) = pathlinkInFlow(pi, nextli, recClass) + moved;
                            end
                        end

                        % 删除该批
                        numRemove = numel(rowsIdx);
                        remaining = cumulativepnum(li) - numRemove;
                        cfCols = li + (0:(numCFfields-1))*NET.numLink;
                        if remaining > 0
                            cumulativeflow(1:remaining, cfCols) = ...
                                cumulativeflow((1+numRemove):(numRemove+remaining), cfCols);
                        end
                        cumulativeflow((remaining+1):(remaining+numRemove), cfCols) = 0;
                        cumulativepnum(li) = remaining;

                        actualcapacity = actualcapacity - totalBatch;
                        if cumulativepnum(li) == 0, break; end
                        startki = cumulativeflow(1, li + 2*NET.numLink);

                    else
                        % 部分放行
                        denom     = max(sum(cumulativeflow(rowsIdx, li)), eps);
                        giveTotal = availCap;
                        for rr = 1:numel(rowsIdx)
                            rowi     = rowsIdx(rr);
                            pi       = cumulativeflow(rowi, li + NET.numLink);
                            recClass = cumulativeflow(rowi, li + 3*NET.numLink);
                            idx_li   = cumulativeflow(rowi, li + 6*NET.numLink);
                            if idx_li <= 0
                                idx_li = find(NET.odPair(pi,:)==li, 1, 'first');
                            end

                            moved = cumulativeflow(rowi, li)/denom * giveTotal;

                            [soc_after, rem_after] = update_batch_SOC(rowi, li, perVeh_kwh);

                            if perVeh_kwh > 0 && moved > 0 && recClass>=1 && recClass<=PARA.numClasses
                                linkChargeEnergy_byClass(li, ki, recClass) = linkChargeEnergy_byClass(li, ki, recClass) + perVeh_kwh * moved;
                            end

                            if idx_li == NET.flagInfo(pi,2)
                                pathoutflow_pk(pi, ki, recClass) = pathoutflow_pk(pi, ki, recClass) + moved;
                            else
                                nextli = NET.odPair(pi, idx_li+1);
                                pathlinkInFlow(pi, nextli, recClass) = pathlinkInFlow(pi, nextli, recClass) + moved;
                            end
                            cumulativeflow(rowi, li) = cumulativeflow(rowi, li) - moved;
                        end
                        break;
                    end
                end
            end
        end

        % 3) 路径累计出流
        for pi = 1:NET.maxnumPath
            for c = 1:PARA.numClasses
                if ki==1
                    pathAccuOutFlow(pi,ki,c) = pathoutflow_pk(pi,ki,c);
                else
                    pathAccuOutFlow(pi,ki,c) = pathAccuOutFlow(pi,ki-1,c) + pathoutflow_pk(pi,ki,c);
                end
            end
        end

        % 4) 写入 cumulativeflow（新注入批次）
        for odi = 1:NET.numOdPair
            rows = (odi-1)*NET.maxnumPathperOd+1 : (odi-1)*NET.maxnumPathperOd+NET.flagInfo((odi-1)*NET.maxnumPathperOd+1,1);
            odisumout = sum(sum(pathAccuOutFlow(rows, ki, :)));

            for pi = rows
                validLen = NET.flagInfo(pi,2);
                if validLen<=0, continue; end
                linksOnPath = NET.odPair(pi, 1:validLen);
                for pos = 1:validLen
                    li = linksOnPath(pos);
                    for c = 1:PARA.numClasses
                        inj = pathlinkInFlow(pi, li, c);
                        if inj <= 0, continue; end

                        if cumulativepnum(li) + 1 > size(cumulativeflow,1)
                            cumulativeflow = [cumulativeflow; zeros(blkRows, numCFfields*NET.numLink)];
                        end
                        cumulativepnum(li) = cumulativepnum(li) + 1;
                        row = cumulativepnum(li);

                        cumulativeflow(row, li)                 = inj;
                        cumulativeflow(row, li + NET.numLink)   = pi;
                        cumulativeflow(row, li + 2*NET.numLink) = ki;
                        cumulativeflow(row, li + 3*NET.numLink) = c;

                        base_demand = PARA.chargeDemandPerClass(c);
                        if pi<=size(pathRemainingCharge,1) && ki<=size(pathRemainingCharge,2) && c<=size(pathRemainingCharge,3)
                            batch_rem = pathRemainingCharge(pi,ki,c);
                            if batch_rem<=0, batch_rem = base_demand; end
                        else
                            batch_rem = base_demand;
                        end
                        init_soc = PARA.SOCinitVec(c);

                        cumulativeflow(row, li + 4*NET.numLink) = init_soc;   % SOC_e
                        cumulativeflow(row, li + 5*NET.numLink) = batch_rem;  % 剩余固定需求
                        cumulativeflow(row, li + 6*NET.numLink) = pos;        % 路径中的位置
                    end
                end
            end
            maxsumoutflow(odi) = max(maxsumoutflow(odi), odisumout);
        end

        % 5) 汇总链路入流
        for c = 1:PARA.numClasses
            linkInFlow_byClass(:,ki,c) = squeeze(sum(pathlinkInFlow(:,:,c),1))';
        end
        linkInFlow(:,ki) = sum(linkInFlow_byClass(:,ki,:),3);

        % 6) 队列与行程时间
        for li = 1:NET.numLink
            cap_li = linkCapacity(li);
            if ki==1
                linkQueue(li,ki) = max(linkInFlow(li,ki) - cap_li, 0);
            else
                linkQueue(li,ki) = max(linkQueue(li,ki-1) + (linkInFlow(li,ki) - cap_li), 0);
            end

            fft = freeFlowTimes(li);
            qf  = linkQueue(li,ki)/max(cap_li, eps_val);

            if hasWireless && wirelessLinks(li)
                linkTrlTime(li,ki) = fft + 0.2/PARA.eta*qf;
            else
                linkTrlTime(li,ki) = fft + 0.2*qf;
            end
        end

        % 7) 写入 WCL 充电总量（该时刻）
        linkChargeEnergy(:,ki) = sum(linkChargeEnergy_byClass(:,ki,:), 3);
    end

    % ---- 写回，用于成本函数 ----
    NET.linkChargeEnergy_byClass = linkChargeEnergy_byClass; % [link x t x class] kWh
    NET.linkChargeEnergy         = linkChargeEnergy;         % [link x t] kWh

    % ---------- 内部：批次级更新 ----------
    function [soc_after, rem_after] = update_batch_SOC(rowi, li_local, perVeh_kwh_local)
        soc_col = li_local + 4*NET.numLink;
        rem_col = li_local + 5*NET.numLink;

        prev_soc = cumulativeflow(rowi, soc_col);
        prev_rem = cumulativeflow(rowi, rem_col);

        % 固定需求：被 WCL 抵扣；到达站点则置 0
        rem_after = max(0, prev_rem - perVeh_kwh_local);
        if hasStation && stationLinks(li_local)
            rem_after = 0;
        end

        % SOC_e 仅用于可行性/诊断（+WCL - 行驶能耗）
        cons_kWh = linkLengthKm(li_local) * PARA.energyPerKm;
        d_soc_w  = perVeh_kwh_local / PARA.BatteryCapacity_kWh;
        d_soc_c  = cons_kWh         / PARA.BatteryCapacity_kWh;
        soc_after = max(0, min(1, prev_soc + d_soc_w) - d_soc_c);

        cumulativeflow(rowi, soc_col) = soc_after;
        cumulativeflow(rowi, rem_col) = rem_after;

        % 同步少量快照（可选）
        pi_local = cumulativeflow(rowi, li_local + NET.numLink);
        od_dep   = cumulativeflow(rowi, li_local + 2*NET.numLink);
        recClass = cumulativeflow(rowi, li_local + 3*NET.numLink);
        if od_dep > 0
            FLOW.pathRemainingCharge(pi_local, od_dep, recClass) = rem_after;
            FLOW.pathSOC_e(pi_local, od_dep, recClass)           = soc_after;
        end
    end
end

%% 4) 计算路径旅行时间
function pathTT = get_travel_time(linkTrlTime)
    global NET PARA

    pathTT = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    validPaths = find(NET.flagInfo(:,2)>0);
    pathLens = NET.flagInfo(:,2);
    hasWireless = isfield(NET,'isWireless');
    if hasWireless
        wirelessLinks = NET.isWireless == 1;
    else
        wirelessLinks = false(NET.numLink,1);
    end
    hasStation = isfield(NET,'isStationLink');
    if hasStation
        stationLinks = NET.isStationLink == 1;
    else
        stationLinks = false(NET.numLink,1);
    end

    for ki = 1:PARA.numSubInterval
        for idx = 1:numel(validPaths)
            pi = validPaths(idx);
            pathLen = pathLens(pi);
            links = NET.odPair(pi,1:pathLen);
            for c = 1:PARA.numClasses
                rem_need = PARA.chargeDemandPerClass(c);   % 固定需求剩余（仅随 WCL 抵扣、站点补齐为0）
                for li = links
                    % ---- 行程时间插值 ----
                    if NET.linkAttr(li,5) <= 0
                        addtime = 0;
                    else
                        baseIdx  = ki + floor(pathTT(pi,ki,c));
                        % ★ 修正：使用 numInterval
                        baseIdx  = max(1, min(baseIdx, PARA.numInterval - 1));
                        tt_floor = linkTrlTime(li, baseIdx);
                        tt_ceil  = linkTrlTime(li, baseIdx+1);
                        frac     = pathTT(pi,ki,c) - floor(pathTT(pi,ki,c));
                        addtime  = tt_floor + frac*(tt_ceil - tt_floor);
                    end

                    % ---- WCL 抵扣 rem_need ----
                    if hasWireless && wirelessLinks(li) && NET.linkAttr(li,5) > 0
                        wcl_kwh = PARA.WCLchargePower * (addtime * PARA.dt_hr);
                        rem_need = max(0, rem_need - wcl_kwh);
                    end

                    % ---- 任意站点：若 rem_need>0，则在此链补齐并加一次站点时间 ----
                    tcs = 0;
                    if hasStation && stationLinks(li) && rem_need > 0
                        tcs_h = rem_need / PARA.stationChargerPower;  % 小时
                        tcs   = max(1, round(tcs_h / PARA.dt_hr));     % 转为仿真步
                        rem_need = 0;                                   % 一次补齐
                    end

                    pathTT(pi,ki,c) = pathTT(pi,ki,c) + addtime + tcs;
                end
            end
        end
    end
end

%% 5) 计算路径成本
function pathTC = get_travel_cost(linkTrlTime)
    global FLOW NET PARA

    % 先算路径旅行时间（包含任意站点的一次补齐时间）
    pathTT = get_travel_time(linkTrlTime);

    pathTC = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    validPaths = find(NET.flagInfo(:,2)>0);
    pathLens = NET.flagInfo(:,2);
    hasWireless = isfield(NET,'isWireless');
    if hasWireless
        wirelessLinks = NET.isWireless == 1;
    else
        wirelessLinks = false(NET.numLink,1);
    end

    for ki = 1:PARA.numSubInterval
        for idx = 1:numel(validPaths)
            pi = validPaths(idx);
            pathLen = pathLens(pi);
            links = NET.odPair(pi,1:pathLen);
            for c = 1:PARA.numClasses
                % ---- 时间成本 + 早晚惩罚（单车）----
                Tpk      = pathTT(pi,ki,c);
                timeCost = PARA.timeunit * Tpk;
                earlytime= PARA.workinterval - PARA.delta - (ki + Tpk);
                latetime = (ki + Tpk) - (PARA.workinterval + PARA.delta);
                earlate  = (earlytime>0)*PARA.earlyunit*earlytime + (latetime>0)*PARA.lateunit*latetime;

                % ---- 行驶能耗费用（单车，可选保留）----
                energyCost = 0;
                for li = links
                    if NET.linkAttr(li,5) > 0
                        energyCost = energyCost + PARA.energyPricePerKWh * NET.linkAttr(li,4) * PARA.energyPerKm;
                    end
                end

                % ---- WCL 与 CS 费用（单车）----
                base_demand = PARA.chargeDemandPerClass(c);
                wcl_total   = 0;

                % 与 pathTT 的插值一致：重走一遍链路时间（单车轨迹）
                tmpTT = 0;
                for li = links
                    if NET.linkAttr(li,5) <= 0
                        addtime = 0;
                    else
                        baseIdx  = ki + floor(tmpTT);
                        % ★ 修正：使用 numInterval
                        baseIdx  = max(1, min(baseIdx, PARA.numInterval - 1));
                        tt_floor = linkTrlTime(li, baseIdx);
                        tt_ceil  = linkTrlTime(li, baseIdx+1);
                        frac     = tmpTT - floor(tmpTT);
                        addtime  = tt_floor + frac*(tt_ceil - tt_floor);
                    end
                    if hasWireless && wirelessLinks(li) && NET.linkAttr(li,5) > 0
                        wcl_total = wcl_total + PARA.WCLchargePower * (addtime * PARA.dt_hr);
                    end
                    tmpTT = tmpTT + addtime;
                end

                wcl_total = min(base_demand, max(0, wcl_total));
                cs_need   = max(0, base_demand - wcl_total);

                wclCost   = PARA.WCLpricePerKWh     * wcl_total;   % 单车在 WCL 上买的电
                csCost    = PARA.stationPricePerKWh * cs_need;     % 单车在站点补齐的电

                % ---- 单车总成本（DUE 中的个体效用）----
                pathTC(pi,ki,c) = timeCost + earlate + energyCost + wclCost + csCost;
            end
        end
    end
end

%% 6) 路径流量分配
function fcratio = gap_func_and_distribute_flow_pattern(iter, objMatrix)
    global NET PARA FLOW

    % 调整rho的大小
    rhoAdjusted = PARA.rho * 1 / ceil(iter / PARA.rhoBase);

    % 初始化gap值
    gap = zeros(NET.numOdPair, 1);
    gapBase = zeros(NET.numOdPair, 1);

    % 临时存储路径流量
    FLOW.tmpPathFlow = zeros(size(FLOW.pathFlow));

    % 遍历每个OD对
    for i = 1:NET.numOdPair
        Odstart = (i - 1) * NET.maxnumPathperOd + 1;
        Odend = (i - 1) * NET.maxnumPathperOd + NET.flagInfo((i - 1) * NET.maxnumPathperOd + 1, 1);
        
        % 如果没有路径，则跳过该OD
        if Odend < Odstart
            continue;
        end
        rows = Odstart:Odend;

        % 遍历每个用户类别
        for c = 1:PARA.numClasses
            tmpFlow = FLOW.pathFlow(rows, :, c);       % [P_i × T]
            tmpObj = objMatrix(rows, :, c);           % [P_i × T]
            vecObj = tmpObj(:);                       % [P_i*T × 1]

            % 计算最小的目标函数值
            minObj = min(vecObj);
            minMask = vecObj < minObj + 1e-5;
            nonMinMask = ~minMask;

            % 计算gap
            gap(i) = gap(i) + sum(sum((tmpObj - minObj).*tmpFlow));
            gapBase(i) = gapBase(i) + minObj * sum(tmpFlow(:));

            % 扁平化路径流量
            flatFlow = tmpFlow(:);

            tmpV = sum(flatFlow(nonMinMask));

            % 更新非最小目标值的路径流量
            flatFlow(nonMinMask) = max(0, flatFlow(nonMinMask) - ...
                rhoAdjusted * flatFlow(nonMinMask) .* (vecObj(nonMinMask) - minObj));

            psi = tmpV - sum(flatFlow(nonMinMask));
            minCount = max(nnz(minMask), 1);
            flatFlow(minMask) = flatFlow(minMask) + psi / minCount;

            % 将更新后的流量重新赋值
            FLOW.tmpPathFlow(rows, :, c) = reshape(flatFlow, size(tmpFlow));
        end
    end

    % 计算fcratio
    denom = max(sum(gapBase), eps);
    fcratio = sum(gap) / denom;

    % 检查fcratio是否为负值
    if fcratio < 0
        disp('Exception: with minus gap!');
    end

    % 更新路径流量
    FLOW.pathFlow = FLOW.tmpPathFlow;
end

%% 7) 更新路径剩余充电需求
function pathRem0 = build_base_remaining_charge(NET, PARA)
    pathRem0 = zeros(NET.maxnumPath, PARA.numSubInterval, PARA.numClasses);
    for c = 1:PARA.numClasses
        pathRem0(:,:,c) = PARA.chargeDemandPerClass(c);
    end
end

%% 8) Dijkstra 最短路径计算
function shortestpathfun(ri, k, c)
    global NET PARA

    Maxnumber = 1e12;

    % --------- 按类别取参数（兼容标量/向量） ---------
    if numel(PARA.energyPerKm) == 1
        energyPerKm_c = PARA.energyPerKm;
    else
        energyPerKm_c = PARA.energyPerKm(c);
    end

    if numel(PARA.energyPricePerKWh) == 1
        energyPrice_c = PARA.energyPricePerKWh;
    else
        energyPrice_c = PARA.energyPricePerKWh(c);
    end

    if numel(PARA.SOCinitVec) == 1
        SOC_init_c = PARA.SOCinitVec;
    else
        SOC_init_c = PARA.SOCinitVec(c);
    end

    o = NET.origin(ri); % 源节点编号
    index_od = NET.originindex(ri):NET.originindex(ri+1)-1; % 属于该 origin 的 OD 行号范围
    numNode = NET.numNode;
    nodeStartIdx = NET.nodeToStartIdx;

    % --------- 单标签：每个节点一个 GC/EA/SOCe ---------
    GC = Maxnumber * ones(numNode, 1); % 累计广义成本
    EA = Maxnumber * ones(numNode, 1); % 到达时间
    SOCe = -inf * ones(numNode, 1); % 到达时的 SOC_e

    GC(o) = 0.0;
    EA(o) = k; % 从出发子时刻 k 起算
    SOCe(o) = SOC_init_c;

    % 优先队列 Q：键为 GC
    Q = Maxnumber * ones(numNode, 1);
    Q(o) = GC(o);

    PRE = zeros(numNode, 1); % 前驱节点（用于回溯路径）

    % ================== Dijkstra 主循环 ==================
    while any(Q < Maxnumber)
        % 1) 取出当前 GC 最小的节点 i
        [~, q] = min(Q);
        i = q;
        Q(i) = Maxnumber; % 标记为“已永久化”

        idx_i = 0;
        if i <= numel(nodeStartIdx)
            idx_i = nodeStartIdx(i);
        end
        if idx_i == 0
            continue;
        end

        for li = NET.startindex(idx_i):NET.startindex(idx_i+1)-1
            j = NET.endnode(li);   % 弧 (i -> j)

            % 时间插值计算
            t_cur = EA(i);
            if ~isfinite(t_cur)
                continue;
            end
            baseIdx = floor(t_cur);
            baseIdx = max(1, min(baseIdx, size(NET.linkTrlTime, 2) - 1));
            tt_floor = NET.linkTrlTime(li, baseIdx);
            tt_ceil = NET.linkTrlTime(li, baseIdx+1);
            frac = t_cur - baseIdx;
            addEA = tt_floor + frac * (tt_ceil - tt_floor);

            if ~isfinite(addEA) || addEA <= 0
                continue;
            end

            link_hours = addEA * PARA.dt_hr;   % 小时数
            wcl_kWh = 0;
            if isfield(NET, 'isWireless') && NET.isWireless(li) == 1 && NET.linkAttr(li, 5) > 0
                wcl_kWh = PARA.WCLchargePower * link_hours;
            end

            cons_kWh = NET.linkAttr(li, 4) * energyPerKm_c;
            delta_soc_w = wcl_kWh / PARA.BatteryCapacity_kWh;
            delta_soc_c = cons_kWh / PARA.BatteryCapacity_kWh;

            soc_after = min(1.0, SOCe(i) + delta_soc_w) - delta_soc_c;
            if soc_after < 0
                continue; % 路上没电，跳过
            end

            f_arrival = EA(i) + addEA; % 到达时间
            timeCost_link = PARA.timeunit * addEA;
            energyCost_link = energyPrice_c * NET.linkAttr(li, 4) * energyPerKm_c;
            wclCost_link = 0;
            if wcl_kWh > 0
                wclCost_link = PARA.WCLpricePerKWh * wcl_kWh;
            end

            dC_link = timeCost_link + energyCost_link + wclCost_link;
            if dC_link < 0
                dC_link = 0;
            end

            GC_new = GC(i) + dC_link;

            if GC_new < GC(j) - 1e-9
                GC(j) = GC_new;
                EA(j) = f_arrival;
                SOCe(j) = soc_after;
                PRE(j) = i;
                Q(j) = GC_new;
            end
        end
    end

    % 回溯路径并写入 NET.odPair
    NET_newpath = 0;
    for odi = index_od
        endnode = NET.d(odi);
        if ~isfinite(GC(endnode))
            continue;
        end

        cpath0 = -ones(1, NET.maxWidthPath);
        j = NET.maxWidthPath;
        cur = endnode;

        while cur ~= o && j >= 1
            pre = PRE(cur);
            if pre == 0
                break;
            end

            idx_pre = 0;
            if pre <= numel(nodeStartIdx)
                idx_pre = nodeStartIdx(pre);
            end
            if idx_pre == 0
                break;
            end
            e_loc0 = find(NET.endnode(NET.startindex(idx_pre):NET.startindex(idx_pre + 1) - 1) == cur, 1, 'first');
            li = NET.startindex(idx_pre) + e_loc0 - 1;

            cpath0(j) = li;
            cur = pre;
            j = j - 1;
        end

        if cur ~= o
            continue;
        end

        cpath = -ones(1, NET.maxWidthPath);
        cpath(1:NET.maxWidthPath - j) = cpath0(j + 1:NET.maxWidthPath);

        rows = (odi - 1) * NET.maxnumPathperOd + 1 : odi * NET.maxnumPathperOd;
        [~, exists] = ismember(cpath, NET.odPair(rows,:), 'rows');

        if ~exists
            NET_newpath = 1;
            NET.numPath = NET.numPath + 1;
            NET.flagInfo(rows(1), 1) = NET.flagInfo(rows(1), 1) + 1;
            idxrow = rows(1) + NET.flagInfo(rows(1), 1) - 1;
            NET.flagInfo(idxrow, 2) = NET.maxWidthPath - j;
            NET.odPair(idxrow, :) = cpath;
        end
    end

    if NET_newpath
        NET.newpathindicator = 1;
    end
end

%% 9) 绘制路径流量图
function FigureFlowfun()
    global FLOW NET PARA
    x = 8 + (0:PARA.numSubInterval-1)/60;

    for c = 1:PARA.numClasses
        figure('Name', sprintf('路径流量 - %s', PARA.userClassNames{c}), 'NumberTitle', 'off');
        hold on;

        plotted = 0;
        for odi = 1:NET.numOdPair
            nPath = NET.flagInfo((odi-1)*NET.maxnumPathperOd+1,1);
            if nPath <= 0, continue; end
            rows = (odi-1)*NET.maxnumPathperOd + (1:nPath);

            for pi = rows
                y = reshape(FLOW.pathFlow(pi,:,c), 1, []);
                if ~any(y) || all(~isfinite(y)), continue; end
                plot(x, y, 'LineWidth', 1.2, 'DisplayName', sprintf('OD%d 路径%d', odi, pi));
                plotted = plotted + 1;
            end
        end

        grid on
        xlim([8, 10]);
        set(gca, 'XTick', 8:2/6:10, ...
                 'XTickLabel', {'8:00','8:20','8:40','9:00','9:20','9:40','10:00'});
        xlabel('出发时间'); ylabel('路径流量');
        title(sprintf('路径流量 - %s', PARA.userClassNames{c}));

        if plotted > 0
            lgd = legend('show', 'Location','bestoutside', 'Interpreter','none');
            if plotted > 30, lgd.NumColumns = 2; end
        else
            text(8.1, 0.5, '无有效曲线', 'Units','normalized');
        end

        hold off;
    end
end

%% 10) 绘制路径成本图
function FigureCostfun()
    global NET PARA
    x = 8 + (0:PARA.numSubInterval-1)/60;

    for c = 1:PARA.numClasses
        figure('Name', sprintf('路径成本 - %s', PARA.userClassNames{c}), 'NumberTitle', 'off');
        hold on;

        plotted = 0;
        for odi = 1:NET.numOdPair
            nPath = NET.flagInfo((odi-1)*NET.maxnumPathperOd+1,1);
            if nPath <= 0, continue; end
            rows = (odi-1)*NET.maxnumPathperOd + (1:nPath);

            for pi = rows
                y = reshape(NET.pathTC(pi,:,c), 1, []);
                if ~any(isfinite(y)), continue; end
                plot(x, y, 'LineWidth', 1.2, 'DisplayName', sprintf('OD%d 路径%d', odi, pi));
                plotted = plotted + 1;
            end
        end

        grid on
        xlim([8, 10]);
        set(gca, 'XTick', 8:2/6:10, ...
                 'XTickLabel', {'8:00','8:20','8:40','9:00','9:20','9:40','10:00'});
        xlabel('出发时间'); ylabel('路径成本');
        title(sprintf('路径成本 - %s', PARA.userClassNames{c}));

        if plotted > 0
            lgd = legend('show', 'Location','bestoutside', 'Interpreter','none');
            if plotted > 30, lgd.NumColumns = 2; end
        else
            text(8.1, 0.5, '无有效曲线', 'Units','normalized');
        end

        hold off;
    end
end
