# FanPilot

FanPilot is a native macOS menu bar utility for monitoring Intel Mac temperatures and fan speeds, with configurable AppleSMC cooling strategies.

FanPilot 是一款面向 Intel Mac 的原生 macOS 菜单栏散热工具。它可以读取 AppleSMC 温度与风扇转速，并根据用户选择的主控传感器自动调整散热档位。

## 当前状态

- 应用最低系统版本为 macOS 13.0。
- 开发起点为 macOS 26，目前已完成 macOS 13 的主要界面与编译兼容处理。
- 风扇监控与控制目前面向配备 AppleSMC 的 Intel Mac，主要测试机型为 `MacBookPro16,2`。
- 当前开发版本为 `0.1.1`。

## 主要功能

- 读取 AppleSMC 温度传感器与风扇 RPM。
- 在菜单栏显示主控温度、最高风扇转速和风扇图标。
- 菜单栏文字和图标会跟随系统浅色/深色外观变化。
- 在 macOS 13 缺少新版 `fan` SF Symbol 时使用兼容图标或自绘后备图形。
- 支持自动、静音、低速、中速、高速和全速散热档位。
- 支持一个主控传感器和多条“温度 → 档位”规则。
- 支持回落温差、最短档位保持时间、采样间隔和紧急全速温度。
- 升档在达到阈值时立即生效；回落时使用滞后区间，避免风扇档位频繁抖动。
- 支持睡眠唤醒后恢复 Apple 自动控制并重新评估策略。
- 提供只读的电池、充电器和 macOS 电源设置报告。
- 支持简体中文、繁体中文和英文。

## 策略工作流

“当前预设”是应用的全局策略选择。概览页、策略页和风扇评估共享同一个当前预设。

- 切换当前预设时，FanPilot 会立即载入、持久化并应用目标策略。
- 顶部状态胶囊会依次显示“切换策略…”、“策略已生效”，然后回到“监控中”或“控制中”。
- 进入策略页时，页面始终显示当前全局预设的已保存内容。页面编辑使用独立草稿，只有点击“保存策略”才会提交并应用。
- 日常办公、外接显示器、高负载等预设可以修改参数，但不能重命名。
- 修改并保存非自定义预设后，策略名和顶部预设名称会显示 `*`，表示它已偏离内置默认值。
- 点击“恢复 <当前预设> 默认值”会重置当前预设并清除 `*`。
- “自定义”策略允许重命名，其名称、规则和高级设置都会单独保存。
- 恢复“自定义”默认值会重置名称和整个策略页。
- 已修改预设和自定义策略在切换预设或重启应用后仍会保留。

## 安全模型

FanPilot 的控制目标是提前散热或增强散热，不会将风扇转速设置低于 Apple 默认最低值。

开启风扇控制后，应用会通过 AppleSMC 写入每个风扇的控制模式和目标转速。任何读取或写入失败都会让应用回到监控模式，并保留恢复 Apple 自动控制的入口。

界面会分开显示以下状态：

- AppleSMC 可读
- Helper 已安装
- 风扇控制已启用
- 写入受限
- 仅监控

## Helper 与权限

风扇控制在首次安装或更新本地 helper 时需要管理员授权。FanPilot 会将 helper 安装到：

```text
/Library/PrivilegedHelperTools/com.local.FanPilot.SMCProbe
```

当前开发版使用管理员授权的 AppleScript 安装和更新 helper。已安装且兼容的 helper 会在下次启动时被直接复用。

如果 helper 丢失、损坏或无法访问 AppleSMC，请在“安全与权限”页面中执行“安装 / 更新 Helper”。

## 系统与开发要求

- macOS 13.0 或更高版本
- Intel Mac（用于实际 AppleSMC 风扇控制）
- Xcode 15+ 或版本匹配的 Xcode Command Line Tools
- Swift 5.9+（用于 Swift Package Manager 与测试）

> `build-app.sh` 默认按当前 Mac 的 CPU 架构编译。Apple Silicon 目前不支持实际的 AppleSMC 风扇控制。

## 构建应用

```sh
./scripts/build-app.sh
```

构建产物位于：

```text
build/FanPilot.app
```

构建脚本会：

1. 编译 FanPilot 主程序和 `FanPilotSMCProbe` helper。
2. 从 `Resources/AppIcon.png` 生成 16、32、128、256、512 以及 Retina 倍率的全套图标。
3. 生成 `AppIcon.icns` 并写入应用包。建议源图标使用 1024×1024 RGBA PNG。
4. 生成 `Info.plist`，将最低系统设为 macOS 13.0。
5. 使用本地 ad-hoc 签名生成可运行的开发版应用包。

## 运行

```sh
open build/FanPilot.app
```

首次使用时，请打开“安全与权限”页面，然后安装或更新授权 helper。

## 测试

```sh
swift test
```

当前回归测试覆盖：

- 温度达到阈值时立即升档。
- 降档时正确使用回落温差。
- 紧急温度强制全速。
- 低于首条规则时回到自动模式。
- 自定义策略重命名与持久化。
- 预设修改 `*` 标记、预设切换、恢复默认和重启恢复。

## 项目结构

```text
FanPilot/
├── Package.swift
├── Resources/
│   └── AppIcon.png
├── Sources/
│   ├── FanPilot/
│   └── FanPilotSMCProbe/
├── Tests/
│   └── FanPilotTests/
└── scripts/
    └── build-app.sh
```

## 已知限制与后续工作

- Apple Silicon 使用不同的硬件控制模型，目前不在支持范围内。
- 开发构建使用 ad-hoc 签名，不是可直接分发的 Developer ID 签名与公证版本。
- 在生产版发布前，授权 helper 应迁移到正式签名的 `SMJobBless` 或 LaunchDaemon/XPC 方案。
- 建议在更多 Intel Mac 机型上验证 SMC key、风扇数量与目标转速行为。

## 本轮更新摘要

- 完成 macOS 13 菜单栏图标和动态文字颜色兼容。
- 重构策略页的草稿、预设、保存、恢复和状态反馈逻辑。
- 增加预设修改标记与按预设分离的持久化存储。
- 修复顶部预设下拉菜单在策略规则编辑期间可能因旧绑定失效而闪退的问题。
- 增加散热策略与持久化回归测试。
- 更新带透明背景的 1024×1024 应用图标，并重新生成全套 macOS 图标资源。
