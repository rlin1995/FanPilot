# FanPilot

FanPilot is a native macOS menu bar and utility-window app for Intel Mac fan monitoring and cooling policy control.

FanPilot 是一款面向 Intel Mac 的 macOS 菜单栏散热工具，用于查看 AppleSMC 温度传感器、监控左右风扇转速，并根据主控传感器自动切换散热档位。

## Features

- Real AppleSMC temperature sensor and fan RPM monitoring
- Native-style macOS utility window with light and dark mode support
- Compact menu bar readout for control-sensor temperature and fan RPM
- Cooling modes: Auto, Quiet, Low, Medium, High, and Full
- One selected control sensor for cooling policy evaluation
- Custom temperature-to-cooling-mode rules
- Hysteresis and minimum hold time to avoid frequent mode switching
- Wake recovery handling after macOS sleep
- Menu bar language selection: Simplified Chinese, Traditional Chinese, and English
- Local authorized helper for AppleSMC fan-control writes

## Safety Model

FanPilot is designed to raise fan targets for earlier or stronger cooling. It does not lower fan speed below Apple's default minimum values.

When fan control is enabled, FanPilot writes per-fan mode and target keys through AppleSMC. If a read or write fails, the app returns to monitoring mode and keeps Apple automatic control available.

The app separates these states in the UI:

- AppleSMC readable
- Helper installed
- Fan control enabled
- Write restricted
- Monitoring only

## Helper And Permissions

Fan control requires administrator authorization. FanPilot installs a local helper at:

```text
/Library/PrivilegedHelperTools/com.local.FanPilot.SMCProbe
```

Current development builds install and update the helper through an administrator-authorized AppleScript command. The helper includes a protocol version check so older helper copies are not silently reused by newer app builds.

For a production release, this helper should be migrated to a signed SMJobBless or LaunchDaemon/XPC flow.

## Supported Hardware

FanPilot currently targets Intel MacBook models with AppleSMC fan keys. Development and testing have focused on MacBookPro16,2.

Apple Silicon Macs use a different hardware-control model and are not the current target.

## Build

```sh
./scripts/build-app.sh
```

The app bundle is generated at:

```text
build/FanPilot.app
```

## Run

```sh
open build/FanPilot.app
```

On first use, open Safety and Permissions, then install or update the authorized helper.

## Notes

This project is still evolving. The UI and policy model are intentionally kept separate from raw SMC details so the helper implementation can be hardened without redesigning the app experience.

