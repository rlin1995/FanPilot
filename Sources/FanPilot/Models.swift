import Foundation
import SwiftUI

enum CoolingMode: String, CaseIterable, Identifiable, Codable {
    case automatic
    case quiet
    case low
    case medium
    case high
    case full

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .automatic: return "automatic"
        case .quiet: return "quiet"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        case .full: return "full"
        }
    }

    var title: String {
        switch self {
        case .automatic: return "自动"
        case .quiet: return "静音"
        case .low: return "低速"
        case .medium: return "中速"
        case .high: return "高速"
        case .full: return "全速"
        }
    }

    var rpmRatio: Double {
        switch self {
        case .automatic: return 0
        case .quiet: return 0.22
        case .low: return 0.38
        case .medium: return 0.58
        case .high: return 0.78
        case .full: return 1.0
        }
    }

    var coolingLevel: Int {
        switch self {
        case .automatic: return 0
        case .quiet: return 1
        case .low: return 2
        case .medium: return 3
        case .high: return 4
        case .full: return 5
        }
    }

    var detail: String {
        switch self {
        case .automatic: return "交还系统自动控制"
        case .quiet: return "轻微抬升，尽量安静"
        case .low: return "低负载持续散热"
        case .medium: return "编译、视频会议等中负载"
        case .high: return "高负载提前降温"
        case .full: return "接近最高转速"
        }
    }
}

enum Preset: String, CaseIterable, Identifiable, Codable {
    case daily
    case externalDisplay
    case heavyLoad
    case manualFull
    case custom

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .daily: return "daily"
        case .externalDisplay: return "externalDisplay"
        case .heavyLoad: return "heavyLoad"
        case .manualFull: return "manualFull"
        case .custom: return "custom"
        }
    }

    var title: String {
        switch self {
        case .daily: return "日常办公"
        case .externalDisplay: return "外接显示器"
        case .heavyLoad: return "高负载"
        case .manualFull: return "手动全速"
        case .custom: return "自定义"
        }
    }
}

enum SensorCategory: String, CaseIterable, Identifiable, Codable {
    case all
    case cpu
    case battery
    case enclosure
    case wireless
    case storage
    case other

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .all: return "all"
        case .cpu: return "cpu"
        case .battery: return "battery"
        case .enclosure: return "enclosure"
        case .wireless: return "wireless"
        case .storage: return "storage"
        case .other: return "other"
        }
    }

    var title: String {
        switch self {
        case .all: return "全部"
        case .cpu: return "CPU"
        case .battery: return "电池"
        case .enclosure: return "机身"
        case .wireless: return "无线"
        case .storage: return "存储"
        case .other: return "其他"
        }
    }
}

struct TemperatureSensor: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var category: SensorCategory
    var temperature: Double
    var isFavorite: Bool
}

struct FanReading: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var minimumRPM: Int
    var currentRPM: Int
    var maximumRPM: Int
    var mode: CoolingMode
}

struct CoolingRule: Identifiable, Hashable, Codable {
    var id = UUID()
    var threshold: Double
    var mode: CoolingMode
}

struct StrategySettings: Codable, Hashable {
    var name: String = "日常办公"
    var controlSensorID: String = "TC0P"
    var hysteresis: Double = 5
    var minimumHoldSeconds: Int = 30
    var samplingIntervalSeconds: Double = 2
    var emergencyFullSpeedTemperature: Double = 95
    var restoreAutomaticOnQuit: Bool = true
    var restoreAutomaticAfterWake: Bool = true
    var rules: [CoolingRule] = [
        CoolingRule(threshold: 60, mode: .quiet),
        CoolingRule(threshold: 70, mode: .low),
        CoolingRule(threshold: 80, mode: .medium),
        CoolingRule(threshold: 88, mode: .high),
        CoolingRule(threshold: 94, mode: .full)
    ]

    static func defaults(for preset: Preset) -> StrategySettings {
        var settings = StrategySettings()
        switch preset {
        case .daily:
            settings.name = "日常办公"
            settings.rules = [
                CoolingRule(threshold: 0, mode: .automatic),
                CoolingRule(threshold: 60, mode: .quiet),
                CoolingRule(threshold: 70, mode: .low),
                CoolingRule(threshold: 82, mode: .medium),
                CoolingRule(threshold: 92, mode: .high)
            ]
        case .externalDisplay:
            settings.name = "外接显示器"
            settings.rules = [
                CoolingRule(threshold: 0, mode: .automatic),
                CoolingRule(threshold: 58, mode: .quiet),
                CoolingRule(threshold: 65, mode: .low),
                CoolingRule(threshold: 76, mode: .medium),
                CoolingRule(threshold: 86, mode: .high),
                CoolingRule(threshold: 94, mode: .full)
            ]
        case .heavyLoad:
            settings.name = "高负载"
            settings.rules = [
                CoolingRule(threshold: 0, mode: .quiet),
                CoolingRule(threshold: 60, mode: .low),
                CoolingRule(threshold: 72, mode: .medium),
                CoolingRule(threshold: 82, mode: .high),
                CoolingRule(threshold: 90, mode: .full)
            ]
        case .manualFull:
            settings.name = "手动全速"
            settings.rules = [CoolingRule(threshold: 0, mode: .full)]
        case .custom:
            settings.name = "自定义"
        }
        return settings
    }

    func matchesDefaults(for preset: Preset) -> Bool {
        let defaultSettings = StrategySettings.defaults(for: preset)
        let sortedRules = rules.sorted { $0.threshold < $1.threshold }
        let sortedDefaultRules = defaultSettings.rules.sorted { $0.threshold < $1.threshold }
        let rulesMatch = sortedRules.count == sortedDefaultRules.count
            && zip(sortedRules, sortedDefaultRules).allSatisfy { pair in
                pair.0.threshold == pair.1.threshold && pair.0.mode == pair.1.mode
            }
        return controlSensorID == defaultSettings.controlSensorID
            && hysteresis == defaultSettings.hysteresis
            && minimumHoldSeconds == defaultSettings.minimumHoldSeconds
            && samplingIntervalSeconds == defaultSettings.samplingIntervalSeconds
            && emergencyFullSpeedTemperature == defaultSettings.emergencyFullSpeedTemperature
            && restoreAutomaticOnQuit == defaultSettings.restoreAutomaticOnQuit
            && restoreAutomaticAfterWake == defaultSettings.restoreAutomaticAfterWake
            && rulesMatch
    }
}

enum StrategyApplicationPhase: Equatable {
    case idle
    case switching(Preset)
    case active(Preset)
}

struct CoolingStrategyEvaluator {
    static func mode(
        for temperature: Double,
        rules: [CoolingRule],
        currentMode: CoolingMode,
        hysteresis: Double,
        emergencyTemperature: Double
    ) -> CoolingMode {
        if temperature >= emergencyTemperature {
            return .full
        }

        let sortedRules = rules.sorted { $0.threshold < $1.threshold }
        let candidate = sortedRules.last { temperature >= $0.threshold }?.mode ?? .automatic

        // Hysteresis only delays a downshift. An upshift must happen as soon as
        // the temperature reaches the next rule so cooling is never held back.
        guard candidate.coolingLevel < currentMode.coolingLevel,
              currentMode != .automatic,
              let currentRule = sortedRules.last(where: { $0.mode == currentMode }),
              temperature > currentRule.threshold - max(0, hysteresis) else {
            return candidate
        }
        return currentMode
    }
}

enum HelperInstallState {
    case missing
    case bundled
    case installed
    case attempted
}

enum SMCAccessState {
    case monitorOnly
    case checking
    case available
    case unavailable
    case recovering
}

enum ControlPermissionState {
    case monitorOnly
    case ready
    case active
    case writeRestricted
}

extension Double {
    var temperatureText: String {
        "\(Int(self.rounded()))°C"
    }
}
