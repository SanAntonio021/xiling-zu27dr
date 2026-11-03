# 希翎 ZU27DR 星座图上位机

本仓库保存 ZU27DR FPGA 板卡的 MATLAB 上位机程序，用于实时显示星座图和链路指标，并记录逐包指标与全部 I/Q 星座点。仓库不包含 FPGA 逻辑或固件。

## 文件

- `WPR_Metrics_GUI.m`：推荐的单文件入口，显示星座图、EVM、PER、BER 估算值、MER 和 Rx IF Power，并保存完整采集记录。
- `WPR_GUI.m`、`WPR_GUI.fig`：旧版 GUIDE 界面，仍可独立运行；它的星座点记录与新程序分开。
- `proc_udp1.m`：UDP 数据接收、界面更新、星座点记录。
- `Handshaking.json`、`Constellation.json`：握手和星座数据请求。
- `int2asc2.m`、`parse_json.m`：通信帧辅助函数。
- `Log_UESTC.jpg`：主界面使用的图片资源。

## 运行

需要 MATLAB R2023b、Communications Toolbox 和支持旧版 UDP `udp` 对象接口的 Instrument Control Toolbox。将 MATLAB 当前文件夹切换到本仓库目录，在命令窗口运行推荐入口：

```matlab
WPR_Metrics_GUI
```

界面顶部的 `Board IP` 用于输入板卡地址，端口固定为 `5001`。首次启动默认 `192.168.0.27`；点击 `Apply IP` 后，地址保存在当前电脑的 MATLAB 偏好设置中，下次启动会自动恢复。偏好设置按电脑本地保存，不会同步进 Git；另一台电脑可以独立使用 `192.168.0.28`。

确认 IP 后点 `START` 开始请求和记录，点 `STOP` 停止并保存。采集过程中 IP 控件会锁定。图表保留最近 50 个数据包用于实时观察，记录文件不设固定点数上限。星座点沿用实验室脚本的 QAM-4 和 `I/Q / 150 / sqrt(2)` 归一化。BER 按 `108000` bit 包长从 PER 推算，界面和记录均标为估算值；板卡返回的 `rms` 保留标注为 `Rx IF Power`，不将其解释为 RSSI。

旧版 GUIDE 程序仍可按原方式运行：

```matlab
WPR_GUI
```

## 采集文件

停止记录后，程序在 `constellation_records/constellation_年月日_时分秒/` 下保存：

- `metrics_recording.mat`：逐包原始及归一化 I/Q 点、逐包指标表、扁平星座点表和采集元数据。
- `constellation_points.csv`：每个星座点的包号、包内点号、电脑接收时间、原始及归一化 I/Q。
- `packet_metrics.csv`：逐包接收计数、CRC 计数、`rms`、EVM、MER、PER 和 BER 估算值。
- `dashboard.png`：停止采集时的界面图像。

时间戳是 MATLAB 电脑处理 UDP 接收事件的时间；同一包中的星座点共用该时间，不是 FPGA 对每个采样点分别打的时间戳。即使停止时尚未收到数据，也会保存空表及采集元数据。采集结果保留在本地，不纳入 Git。

## 验证状态

MATLAB R2023b 下已验证无板卡启动、IP 偏好设置恢复、合成数据的指标与星座点记录、重复采集时 PER 重置，以及零数据停止保存。`.27` 与 `.28` 板卡的实时曲线和实板保存结果仍需在实验环境分别检查；本机回环和合成数据验证不代替实板验收。
