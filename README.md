# 第四篇 P4 独立研究开发包 V1

本包交付可执行的物理组件、固定流网络加载原型、VI 数值求解器、维修博弈接口、参数来源表、已有证据保留入口，以及实际计算完成的 10 张参考图和底层表。它尚未完成原 V173 全网络滚动 DUE、G0–G5 正式治理实验或整篇论文数值认证。`PRODUCTION_ADMISSION = CLOSED`。

当前正式工程仍在 `C:\Users\Xiao\Desktop\Four Paper\CODE2\P4_V173_CODE2_WORKSPACE_20261111`。本包只安装到一个新目录；不覆盖生产源码，不重算135组历史实验。

## 本次实际交付

| 内容 | 实现和执行范围 |
|---|---|
| 连续时间端口故障与维修 | 持久化累计风险阈值；改变维修强度不重置未完成维修时钟；每个端口独立事件流，支持CRN |
| 连续质量FCS | FIFO开始服务、正质量不取整、每车功率上限、站点总功率上限、服务中承诺锁定、等待与服务库存分开 |
| WCL | 移动通电时间、效率、牵引能耗、SOC、剩余任务和电池容量；通电段外等待不供能 |
| 固定流网络加载 | 分钟网格、逐链FIFO点队列、分流质量、实际入离链记录、WCL与FCS连接；已执行小型网络验证 |
| CTM | 带发送与接收约束的串联单元组件；未冒充完整网络CTM |
| VI | 有步长回溯的投影外梯度、同一迭代点流量与成本、显式不收敛状态；已通过可解析两路径问题 |
| 维修博弈 | 有限动作集最佳响应和逐方偏离regret；调用者必须提供重新求解后续状态的收益oracle |
| 锁定前缀和资源池 | 有序前缀含当前在途链接；已承诺站点锁定；资源实际到达后生效 |
| 指标 | QSA/SSA/WLA分解、交互项、配对bootstrap、资源优先差距、加权分位数、恢复时间右删失 |
| 输出 | 10张PNG和可编辑SVG；逐样本/逐状态CSV；5种时间尺度×1000条CTMC样本；独立测试日志 |
| 正式论文图 | 8类图的审查后绘图入口；当前没有合格输入，状态表明确列为缺失，不生成替代数值 |

`python/` 是本轮实际执行的计算核心。`matlab/` 提供R2023a原生解析检查、部分数值公式、冻结证据导入与绘图；MATLAB总入口可调用Python重建所有参考图。本轮环境没有MATLAB，因此未声称MATLAB动态验收通过。这里没有把Python运行结果当作MATLAB运行结果。

## 下载后直接查看

打开 `results/REFERENCE_20261117/index.html`。它展示本轮已计算完成的10张图，每张均标记参考/组件研究范围。精确数值在同目录的 `tables/`；`RUN_SUMMARY.json`记录执行范围。

## 独立安装

在解压后的包目录运行PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\INSTALL_P4_RESEARCH.ps1
```

默认新安装目录：

```text
C:\Users\Xiao\Desktop\Four Paper\CODE2\P4_V173_CODE2_WORKSPACE_20261111\01_ACTIVE_CODE_PACKAGES\P4_RESEARCH_V1
```

如果目标已存在，安装停止，不覆盖。`VERIFY_P4_RESEARCH.ps1`逐项核验`MANIFEST.csv`中的字节数和SHA256。

## MATLAB R2023a入口

```matlab
dbclear all;
restoredefaultpath;
clear functions;
rehash;
pkg = 'C:\Users\Xiao\Desktop\Four Paper\CODE2\P4_V173_CODE2_WORKSPACE_20261111\01_ACTIVE_CODE_PACKAGES\P4_RESEARCH_V1';
addpath(pkg,'-begin');
START_P4_RESEARCH_V1('review');
```

这一步验证整个包，实际执行13项MATLAB原生解析/数值检查，并报告随包参考结果。它没有执行正式SF24模型。

重算本包参考结果需要Python 3.10或更高版本和`requirements.txt`中的三个库。可使用已安装的Anaconda环境；在该环境中执行：

```powershell
python -m pip install -r requirements.txt
python python\run.py --out runs\MY_REFERENCE_RUN --mc 1000
```

也可在MATLAB中指定**实际存在的**Python解释器：

```matlab
START_P4_RESEARCH_V1('reproduce', 'C:\实际Python安装目录\python.exe');
```

每次新运行写入独立目录。程序拒绝覆盖已经存在的输出目录。

## 保留你本机已通过的P5-P3结果

```matlab
START_P4_RESEARCH_V1('preserve');
```

入口定位此前确定的`RUN_20261117_005654_211_P5P3`，核验12个成员和3个外部冻结哈希，复核107×2×241张量、3620辆、7538个正单元、两类质量以及全时域连接总量。成功后逐字节复制原ZIP至新目录，并生成4张实际保存流量图。原文件保持不变。

本轮会话恢复后原上传文件的本地副本已不可用，因此**交付ZIP没有装入原P5-P3证据字节**。这里包含的是有冻结锚点的本机导入程序，没有根据聊天数字重新制造原始CSV或MAT。

需要继续打通正式SF24数据接口时，在MATLAB运行：

```matlab
smallBundle = EXPORT_P4_LOCAL_INPUTS();
```

它只打包两个精确哈希匹配的正式网络/107路径MAT及小型P5-P3证据ZIP，不打包365MB父MAT，不读取或重算135组历史实验。之后必须实际检查这些MAT字段，才可把新加载器绑定到原路径身份。

## 补充数据的适用边界

见`config/PARAMETER_PROVENANCE.csv`和`docs/MODEL_AND_DATA_REVIEW.md`。38项参数分别标注论文原设定、公开基准、模型继承、新增机制情景或缺失输入。文献可以为合理范围提供依据，不能提供你原来的路径序列、动态状态或第三篇四个事前均衡。

特别注意：107与491路径口径尚未统一；公开SF24长度不能直接当作km；BPR容量不能直接当作CTM出流与储存；40000/20=2000 kW是等效故障块功率，不能自动当作每辆乘用车功率。

## 正式论文图表入口

```powershell
python python\publish.py --registry config\formal_case_registry.json --out runs\PAPER_FIGURES
```

当前registry为空，程序只生成8项缺失状态。取得真实正式实验后，每个case必须提供按来源hash绑定的`metrics.csv`、`timeseries.csv`和外部审查证书。证书的`scope`须为`FORMAL_P4`。模板默认全部`NOT_GRANTED`，不能仅手工改成PASS来获得科学认证。不同需求等干扰因素必须使用不同`comparison_id`；同一图不能静默混合不同设计。

主文A–J实验尚未由本包执行。当前真正完成的是可复现物理组件、数值接口与隔离固定流测试，以及来源与出版边界的明确化。

## 目录

`python/` 计算、测试、证据读取、正式结果绘图；`matlab/` 原生公式与只读入口；`data/public/` 公开网络原文件及来源hash；`config/` 参数和A–J设计；`results/` 本轮已完成输出；`docs/` 模型差异与后续闭合条件。

原始公开数据的使用条件和出处见`data/public/SOURCES.json`及`docs/REFERENCES.md`。本包独立实现算法；没有复制分发未明确许可的Han MATLAB求解器源码。
