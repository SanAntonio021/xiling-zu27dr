# 希翎 ZU27DR 星座图上位机

本仓库保存 ZU27DR FPGA 板卡的 MATLAB 上位机程序，用于接收并实时显示星座图数据，以及记录接收到的 I/Q 星座点。仓库不包含 FPGA 逻辑或固件。

## 文件

- `WPR_GUI.m`、`WPR_GUI.fig`：主界面和界面布局。
- `proc_udp1.m`：UDP 数据接收、界面更新、星座点记录。
- `Handshaking.json`、`Constellation.json`：握手和星座数据请求。
- `int2asc2.m`、`parse_json.m`：通信帧辅助函数。
- `Log_UESTC.jpg`：主界面使用的图片资源。

## 运行

需要安装支持旧版 UDP `udp` 对象接口的 MATLAB 和 Instrument Control Toolbox。将 MATLAB 当前文件夹切换到本仓库目录，在命令窗口运行：

```matlab
WPR_GUI
```

界面左下角的 `Board IP` 用于输入板卡地址，端口固定为 `5001`。首次启动默认 `192.168.0.27`；点击 `Apply IP` 后，程序会重开 UDP socket，并把地址保存在当前电脑的 MATLAB 偏好设置中，下次启动会自动恢复。偏好设置按电脑本地保存，不会同步进 Git；另一台电脑可以独立使用 `192.168.0.28`。

启动界面后，先确认 `Board IP` 正确；修改过地址时先点 `Apply IP`。然后按原有流程点击系统连接按钮完成握手，再点 `START` 开始请求并显示星座数据，点 `STOP` 结束记录并保存。程序会阻止未应用的 IP 或未完成握手时开始采集。

## 采集文件

停止记录后，程序在 `constellation_records/constellation_年月日_时分秒/` 下保存：

- `constellation_recording.mat`：I/Q 点、包号、包内点号及采集元数据。
- `constellation_points.csv`：可直接分析的星座点表。
- `constellation.png`：本次采集的星座图。

记录的时间是 MATLAB 电脑收到 UDP 包的时间；同一包中的点共用该接收时间，不是 FPGA 对每个采样点分别打的时间戳。采集结果保留在本地，不纳入 Git。

## 验证状态

MATLAB R2023b 下已验证界面启动、IP 切换、本机偏好设置保存与重启恢复，以及 IP 控件布局。`checkcode` 对旧版 `udp`、`instrfind` 接口给出兼容性提示；实际板卡联机采集仍需在实验环境验证。
