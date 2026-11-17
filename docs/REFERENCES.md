# 参考来源与使用方式

检索日期：2026-11-17。公开网页是参数背景或算法参考，不是本研究算例输出。

1. Han, K., Eve, G., Friesz, T. L. (2019). Computing Dynamic User Equilibria on Large-Scale Networks with Software Implementation. *Networks and Spatial Economics*, 19, 869–902. DOI: https://doi.org/10.1007/s11067-018-9433-y 。公开源码：https://github.com/DrKeHan/DTA 。本轮检查DUE_solver、Update和CREATE_NETWORK_PROPERTIES；参考commit `4dcd7e7c5c26711f26a476d6044f452509e2740e`。没有复制其源码进本交付包。
2. Transportation Networks for Research Core Team. https://github.com/bstabler/TransportationNetworks 。SF24：https://github.com/bstabler/TransportationNetworks/tree/master/SiouxFalls 。原文件SHA256见`data/public/SOURCES.json`。数据用于学术研究，发表须说明来源。用户自行承担基于数据的结论责任；这不是现实城市标定数据。
3. 23 CFR 680.116. https://www.ecfr.gov/current/title-23/chapter-I/subchapter-G/part-680/section-680.116 。年度端口uptime严格大于97%；与CTMC无条件可用率的计量口径不同。
4. 23 CFR 680.106(d). https://www.ecfr.gov/current/title-23/chapter-I/subchapter-G/part-680/section-680.106 。相关走廊DCFC的150-kW能力要求用于参考功率边界；并非所有站点或车型的统一功率。
5. Oak Ridge National Laboratory. *Design and Analysis of a 200 kW Dynamic Wireless Charging System for Electric Vehicles*. https://www.osti.gov/servlets/purl/1874650 。公开摘要报告120-kW实验验证及91.31%效率；本包0.90为声明的参考值，不把实验值当成道路实测。
6. ORNL (2024). Charging up the commute. https://www.ornl.gov/news/charging-commute 。100-kW车辆无线充电实验提供技术背景；静态展示不能直接证明动态道路效率。
7. US DOE Alternative Fuels Data Center. https://afdc.energy.gov/fuels/electricity-stations 。充电时间受电池容量、SOC、车辆和设备功率等共同限制。

用户稿件与总设计文件已在本轮之前读取。当前续接会话缺少其原字节副本；未将稿件或作者个人信息公开上传。源码、参数表与文档明确区分原稿设定、新参考情景和缺失输入。
