# FanPilot

FanPilot is a native macOS menu bar and utility-window prototype for Intel Mac fan monitoring and cooling policy control.
FanPilot 是一款原生 macOS 菜单栏工具窗口原型程序，用于英特尔芯片 Mac 的风扇状态监控与散热策略管控。

# Current build 当前版本功能：
Shows a complete macOS-style main window. 提供完整 macOS 原生风格主窗口界面。
Shows a menu bar item with temperature and fan RPM. 菜单栏常驻显示温度与风扇转速（RPM）。
Supports presets, a single control sensor, cooling rules, favorites, and safety status. 支持预设方案、独立控制传感器、散热规则、收藏配置以及安全状态提示。
Uses a simulated hardware monitor while the SMC/helper layer is being connected. 在 SMC 底层 / 辅助驱动层对接完成前，采用模拟硬件监控模块运行。
术语补充说明
SMC：System Management Controller，系统管理控制器，Mac 负责风扇、温度、电源管理的底层芯片
RPM：转 / 分钟，风扇转速单位
menu bar：macOS 屏幕顶部菜单栏
presets：散热预设档位（静音 / 均衡 / 强散热等）

Build:

```sh
./scripts/build-app.sh
```

Run:

```sh
open build/FanPilot.app
```

The first hardware-control release should replace `SimulatedHardwareMonitor` with a privileged helper-backed SMC implementation. The app is intentionally written so the UI and policy model do not depend on raw SMC details.
