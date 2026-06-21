import Foundation

protocol HardwareMonitoring {
    func readSnapshot() -> HardwareSnapshot
    func useRealHardware()
    func disableRealHardware()
    func detectInstalledHelper() -> Bool
    func prepareControl() throws -> String
    func diagnose() throws -> String
    func fanKeys() throws -> String
    func testWrite(mode: CoolingMode, fans: [FanReading], useForceMask: Bool) throws
    func testModeKeyWrite(mode: CoolingMode, fans: [FanReading]) throws
    func testMinimumWrite(mode: CoolingMode, fans: [FanReading]) throws
    func restoreMinimums(fans: [FanReading]) throws
    func apply(mode: CoolingMode, to fans: [FanReading]) throws
    func restoreAutomatic() throws
    func uninstallHelper() throws
}

struct HardwareSnapshot {
    var modelIdentifier: String
    var sensors: [TemperatureSensor]
    var fans: [FanReading]
    var controlAvailable: Bool
    var controlStatusText: String
}

final class SMCBackedHardwareMonitor: HardwareMonitoring {
    private let fallback = SimulatedHardwareMonitor()
    private let probe = SMCProbeRunner()
    private var realHardwareEnabled = false
    private var lastGoodSnapshot: HardwareSnapshot?

    func readSnapshot() -> HardwareSnapshot {
        guard realHardwareEnabled else {
            var snapshot = fallback.readSnapshot()
            snapshot.controlStatusText = "安全启动模式，使用模拟数据"
            return snapshot
        }
        do {
            let snapshot = try probe.snapshot()
            let sensors = snapshot.sensors
            let fans = snapshot.fans
            guard !sensors.isEmpty || !fans.isEmpty else {
                if var lastGoodSnapshot {
                    lastGoodSnapshot.controlStatusText = "AppleSMC 恢复中，显示上次数据"
                    return lastGoodSnapshot
                }
                return fallbackSnapshot(reason: "AppleSMC 未返回可识别传感器")
            }
            let resolvedSnapshot = HardwareSnapshot(
                modelIdentifier: snapshot.modelIdentifier,
                sensors: sensors.isEmpty ? (lastGoodSnapshot?.sensors ?? fallback.readSnapshot().sensors) : sensors,
                fans: fans.isEmpty ? (lastGoodSnapshot?.fans ?? fallback.readSnapshot().fans) : fans,
                controlAvailable: true,
                controlStatusText: sensors.isEmpty || fans.isEmpty ? "AppleSMC 恢复中，显示部分上次数据" : "AppleSMC 监控"
            )
            if !sensors.isEmpty || !fans.isEmpty {
                lastGoodSnapshot = resolvedSnapshot
            }
            return resolvedSnapshot
        } catch {
            realHardwareEnabled = false
            if var lastGoodSnapshot {
                lastGoodSnapshot.controlAvailable = false
                lastGoodSnapshot.controlStatusText = "AppleSMC 暂时不可用，显示上次数据"
                return lastGoodSnapshot
            }
            return fallbackSnapshot(reason: error.localizedDescription)
        }
    }

    func apply(mode: CoolingMode, to fans: [FanReading]) throws {
        realHardwareEnabled = true
        try probe.applyModeKeys(mode: mode, fans: fans)
    }

    func testWrite(mode: CoolingMode, fans: [FanReading], useForceMask: Bool) throws {
        realHardwareEnabled = true
        if useForceMask {
            try probe.applyForce(mode: mode, fans: fans)
        } else {
            try probe.apply(mode: mode, fans: fans)
        }
    }

    func testModeKeyWrite(mode: CoolingMode, fans: [FanReading]) throws {
        realHardwareEnabled = true
        try probe.applyModeKeys(mode: mode, fans: fans)
    }

    func testMinimumWrite(mode: CoolingMode, fans: [FanReading]) throws {
        realHardwareEnabled = true
        try probe.applyMinimum(mode: mode, fans: fans)
    }

    func restoreMinimums(fans: [FanReading]) throws {
        realHardwareEnabled = true
        try probe.restoreMinimums(fans: fans)
    }

    func restoreAutomatic() throws {
        guard realHardwareEnabled else { return }
        try probe.restoreAutomatic()
    }

    func useRealHardware() {
        realHardwareEnabled = true
    }

    func disableRealHardware() {
        realHardwareEnabled = false
    }

    func detectInstalledHelper() -> Bool {
        guard probe.isPrivilegedHelperInstalled else { return false }
        realHardwareEnabled = true
        return true
    }

    func prepareControl() throws -> String {
        realHardwareEnabled = true
        try probe.installPrivilegedHelper()
        try probe.probe()
        return probe.isPrivilegedHelperInstalled ? "授权 helper 已安装" : "SMC 探测工具"
    }

    func diagnose() throws -> String {
        realHardwareEnabled = true
        return try probe.diagnose()
    }

    func fanKeys() throws -> String {
        realHardwareEnabled = true
        return try probe.fanKeys()
    }

    func uninstallHelper() throws {
        try probe.uninstallPrivilegedHelper()
        realHardwareEnabled = false
    }

    private func fallbackSnapshot(reason: String) -> HardwareSnapshot {
        var snapshot = fallback.readSnapshot()
        snapshot.controlAvailable = false
        snapshot.controlStatusText = reason + "，使用模拟数据"
        return snapshot
    }
}

final class SimulatedHardwareMonitor: HardwareMonitoring {
    private var tick: Double = 0

    func readSnapshot() -> HardwareSnapshot {
        tick += 0.35
        let wave = sin(tick)
        let cpu = 76 + wave * 9
        let fans = [
            FanReading(
                id: "F0Ac",
                name: "Left side",
                minimumRPM: 1250,
                currentRPM: Int(3600 + max(0, cpu - 70) * 155),
                maximumRPM: 6336,
                mode: .automatic
            ),
            FanReading(
                id: "F1Ac",
                name: "Right side",
                minimumRPM: 1350,
                currentRPM: Int(3800 + max(0, cpu - 70) * 165),
                maximumRPM: 6864,
                mode: .automatic
            )
        ]
        let sensors = [
            TemperatureSensor(id: "TC0P", name: "CPU Core (average)", category: .cpu, temperature: cpu, isFavorite: true),
            TemperatureSensor(id: "TC1C", name: "CPU Core 1", category: .cpu, temperature: cpu + 4, isFavorite: true),
            TemperatureSensor(id: "TC2C", name: "CPU Core 2", category: .cpu, temperature: cpu - 2, isFavorite: false),
            TemperatureSensor(id: "TB0T", name: "Battery Max", category: .battery, temperature: 39 + wave * 2, isFavorite: true),
            TemperatureSensor(id: "TB1T", name: "Battery Sensor 1", category: .battery, temperature: 38 + wave, isFavorite: false),
            TemperatureSensor(id: "TW0P", name: "Airport Proximity", category: .wireless, temperature: 52 + wave * 4, isFavorite: true),
            TemperatureSensor(id: "TH0x", name: "Palm Rest", category: .enclosure, temperature: 34 + wave * 1.5, isFavorite: false),
            TemperatureSensor(id: "TS0P", name: "SSD", category: .storage, temperature: 45 + wave * 3, isFavorite: true)
        ]
        return HardwareSnapshot(
            modelIdentifier: "MacBookPro16,2",
            sensors: sensors,
            fans: fans,
            controlAvailable: false,
            controlStatusText: "模拟监控模式"
        )
    }

    func apply(mode: CoolingMode, to fans: [FanReading]) throws {
        throw HardwareControlError.unavailable
    }

    func useRealHardware() {}
    func disableRealHardware() {}
    func detectInstalledHelper() -> Bool { false }

    func prepareControl() throws -> String {
        throw HardwareControlError.unavailable
    }

    func diagnose() throws -> String {
        throw HardwareControlError.unavailable
    }

    func fanKeys() throws -> String {
        throw HardwareControlError.unavailable
    }

    func testWrite(mode: CoolingMode, fans: [FanReading], useForceMask: Bool) throws {
        throw HardwareControlError.unavailable
    }

    func testModeKeyWrite(mode: CoolingMode, fans: [FanReading]) throws {
        throw HardwareControlError.unavailable
    }

    func testMinimumWrite(mode: CoolingMode, fans: [FanReading]) throws {
        throw HardwareControlError.unavailable
    }

    func restoreMinimums(fans: [FanReading]) throws {
        throw HardwareControlError.unavailable
    }

    func restoreAutomatic() throws {}
    func uninstallHelper() throws {}
}
