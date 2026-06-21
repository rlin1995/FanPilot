# FanPilot

FanPilot is a native macOS menu bar and utility-window prototype for Intel Mac fan monitoring and cooling policy control.

Current build:

- Shows a complete macOS-style main window.
- Shows a menu bar item with temperature and fan RPM.
- Supports presets, a single control sensor, cooling rules, favorites, and safety status.
- Uses a simulated hardware monitor while the SMC/helper layer is being connected.

Build:

```sh
./scripts/build-app.sh
```

Run:

```sh
open build/FanPilot.app
```

The first hardware-control release should replace `SimulatedHardwareMonitor` with a privileged helper-backed SMC implementation. The app is intentionally written so the UI and policy model do not depend on raw SMC details.
