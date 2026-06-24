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
        case .automatic: "automatic"
        case .quiet: "quiet"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .full: "full"
        }
    }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .quiet: "静音"
        case .low: "低速"
        case .medium: "中速"
        case .high: "高速"
        case .full: "全速"
        }
    }

    var rpmRatio: Double {
        switch self {
        case .automatic: 0
        case .quiet: 0.22
        case .low: 0.38
        case .medium: 0.58
        case .high: 0.78
        case .full: 1.0
        }
    }

    var detail: String {
        switch self {
        case .automatic: "交还系统自动控制"
        case .quiet: "轻微抬升，尽量安静"
        case .low: "低负载持续散热"
        case .medium: "编译、视频会议等中负载"
        case .high: "高负载提前降温"
        case .full: "接近最高转速"
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
        case .daily: "daily"
        case .externalDisplay: "externalDisplay"
        case .heavyLoad: "heavyLoad"
        case .manualFull: "manualFull"
        case .custom: "custom"
        }
    }

    var title: String {
        switch self {
        case .daily: "日常办公"
        case .externalDisplay: "外接显示器"
        case .heavyLoad: "高负载"
        case .manualFull: "手动全速"
        case .custom: "自定义"
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
        case .all: "all"
        case .cpu: "cpu"
        case .battery: "battery"
        case .enclosure: "enclosure"
        case .wireless: "wireless"
        case .storage: "storage"
        case .other: "other"
        }
    }

    var title: String {
        switch self {
        case .all: "全部"
        case .cpu: "CPU"
        case .battery: "电池"
        case .enclosure: "机身"
        case .wireless: "无线"
        case .storage: "存储"
        case .other: "其他"
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
