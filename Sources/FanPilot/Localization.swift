import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case simplifiedChinese
    case traditionalChinese
    case english

    var id: String { rawValue }

    var nativeTitle: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        }
    }
}

struct Localizer {
    let language: AppLanguage

    func text(_ key: String) -> String {
        Self.table[key]?[language] ?? Self.table[key]?[.simplifiedChinese] ?? key
    }

    private static let table: [String: [AppLanguage: String]] = [
        "overview": [.simplifiedChinese: "概览", .traditionalChinese: "概覽", .english: "Overview"],
        "sensors": [.simplifiedChinese: "传感器", .traditionalChinese: "感測器", .english: "Sensors"],
        "strategy": [.simplifiedChinese: "策略", .traditionalChinese: "策略", .english: "Strategy"],
        "safety": [.simplifiedChinese: "安全与权限", .traditionalChinese: "安全與權限", .english: "Safety"],
        "currentPreset": [.simplifiedChinese: "当前预设", .traditionalChinese: "目前預設", .english: "Preset"],
        "monitoring": [.simplifiedChinese: "监控中", .traditionalChinese: "監控中", .english: "Monitoring"],
        "controlling": [.simplifiedChinese: "控制中", .traditionalChinese: "控制中", .english: "Controlling"],
        "restoreAuto": [.simplifiedChinese: "恢复自动", .traditionalChinese: "恢復自動", .english: "Restore Auto"],
        "restoreAppleAuto": [.simplifiedChinese: "恢复 Apple 自动控制", .traditionalChinese: "恢復 Apple 自動控制", .english: "Restore Apple Auto"],
        "openFanPilot": [.simplifiedChinese: "打开 FanPilot", .traditionalChinese: "開啟 FanPilot", .english: "Open FanPilot"],
        "quit": [.simplifiedChinese: "退出", .traditionalChinese: "結束", .english: "Quit"],
        "language": [.simplifiedChinese: "语言", .traditionalChinese: "語言", .english: "Language"],
        "currentPresetMenu": [.simplifiedChinese: "当前预设", .traditionalChinese: "目前預設", .english: "Preset"],

        "automatic": [.simplifiedChinese: "自动", .traditionalChinese: "自動", .english: "Auto"],
        "quiet": [.simplifiedChinese: "静音", .traditionalChinese: "靜音", .english: "Quiet"],
        "low": [.simplifiedChinese: "低速", .traditionalChinese: "低速", .english: "Low"],
        "medium": [.simplifiedChinese: "中速", .traditionalChinese: "中速", .english: "Medium"],
        "high": [.simplifiedChinese: "高速", .traditionalChinese: "高速", .english: "High"],
        "full": [.simplifiedChinese: "全速", .traditionalChinese: "全速", .english: "Full"],

        "daily": [.simplifiedChinese: "日常办公", .traditionalChinese: "日常辦公", .english: "Daily"],
        "externalDisplay": [.simplifiedChinese: "外接显示器", .traditionalChinese: "外接顯示器", .english: "External Display"],
        "heavyLoad": [.simplifiedChinese: "高负载", .traditionalChinese: "高負載", .english: "Heavy Load"],
        "manualFull": [.simplifiedChinese: "手动全速", .traditionalChinese: "手動全速", .english: "Manual Full"],
        "custom": [.simplifiedChinese: "自定义", .traditionalChinese: "自訂", .english: "Custom"],

        "all": [.simplifiedChinese: "全部", .traditionalChinese: "全部", .english: "All"],
        "cpu": [.simplifiedChinese: "CPU", .traditionalChinese: "CPU", .english: "CPU"],
        "battery": [.simplifiedChinese: "电池", .traditionalChinese: "電池", .english: "Battery"],
        "enclosure": [.simplifiedChinese: "机身", .traditionalChinese: "機身", .english: "Enclosure"],
        "wireless": [.simplifiedChinese: "无线", .traditionalChinese: "無線", .english: "Wireless"],
        "storage": [.simplifiedChinese: "存储", .traditionalChinese: "儲存", .english: "Storage"],
        "other": [.simplifiedChinese: "其他", .traditionalChinese: "其他", .english: "Other"],

        "fans": [.simplifiedChinese: "风扇", .traditionalChinese: "風扇", .english: "Fans"],
        "fanRPMSubtitle": [.simplifiedChinese: "最低 / 当前 / 最大 RPM", .traditionalChinese: "最低 / 目前 / 最高 RPM", .english: "Minimum / Current / Maximum RPM"],
        "controlSensor": [.simplifiedChinese: "主控传感器", .traditionalChinese: "主控感測器", .english: "Control Sensor"],
        "sensorSubtitle": [.simplifiedChinese: "选择一个传感器作为策略主控", .traditionalChinese: "選擇一個感測器作為策略主控", .english: "Choose one sensor for strategy control"],
        "search": [.simplifiedChinese: "搜索", .traditionalChinese: "搜尋", .english: "Search"],
        "sensorColumn": [.simplifiedChinese: "传感器", .traditionalChinese: "感測器", .english: "Sensor"],
        "temperature": [.simplifiedChinese: "温度", .traditionalChinese: "溫度", .english: "Temperature"],
        "usage": [.simplifiedChinese: "用途", .traditionalChinese: "用途", .english: "Use"],
        "primary": [.simplifiedChinese: "主控", .traditionalChinese: "主控", .english: "Primary"],

        "safetySubtitle": [.simplifiedChinese: "控制风扇需要本地 helper 与管理员授权", .traditionalChinese: "控制風扇需要本機 helper 與管理員授權", .english: "Fan control requires a local helper and admin authorization"],
        "coolingModes": [.simplifiedChinese: "散热档位", .traditionalChinese: "散熱檔位", .english: "Cooling Modes"],
        "status": [.simplifiedChinese: "状态", .traditionalChinese: "狀態", .english: "Status"],
        "helperStatus": [.simplifiedChinese: "Helper 状态", .traditionalChinese: "Helper 狀態", .english: "Helper"],
        "smcAccess": [.simplifiedChinese: "SMC 访问", .traditionalChinese: "SMC 存取", .english: "SMC Access"],
        "lastWrite": [.simplifiedChinese: "最后写入", .traditionalChinese: "最後寫入", .english: "Last Write"],
        "hardwareMode": [.simplifiedChinese: "硬件模式", .traditionalChinese: "硬體模式", .english: "Hardware Mode"],
        "detectAppleSMC": [.simplifiedChinese: "检测 AppleSMC", .traditionalChinese: "偵測 AppleSMC", .english: "Detect AppleSMC"],
        "installUpdateHelper": [.simplifiedChinese: "安装/更新授权 helper", .traditionalChinese: "安裝/更新授權 helper", .english: "Install/Update Helper"],
        "runDiagnostics": [.simplifiedChinese: "运行诊断", .traditionalChinese: "執行診斷", .english: "Run Diagnostics"],
        "scanFanKeys": [.simplifiedChinese: "扫描风扇 Key", .traditionalChinese: "掃描風扇 Key", .english: "Scan Fan Keys"],
        "testTargetRPM": [.simplifiedChinese: "测试目标转速", .traditionalChinese: "測試目標轉速", .english: "Test Target RPM"],
        "testModeKey": [.simplifiedChinese: "测试模式 Key", .traditionalChinese: "測試模式 Key", .english: "Test Mode Key"],
        "testMinimumRPM": [.simplifiedChinese: "测试最低转速", .traditionalChinese: "測試最低轉速", .english: "Test Minimum RPM"],
        "testForceControl": [.simplifiedChinese: "测试强制控制", .traditionalChinese: "測試強制控制", .english: "Test Force Control"],
        "strategySubtitle": [.simplifiedChinese: "根据一个主控传感器自动切换散热档位", .traditionalChinese: "根據一個主控感測器自動切換散熱檔位", .english: "Switch cooling modes from one control sensor"],
        "strategyName": [.simplifiedChinese: "策略名称", .traditionalChinese: "策略名稱", .english: "Strategy Name"],
        "temperatureRules": [.simplifiedChinese: "温度规则", .traditionalChinese: "溫度規則", .english: "Temperature Rules"],
        "addRule": [.simplifiedChinese: "新增规则", .traditionalChinese: "新增規則", .english: "Add Rule"],
        "mode": [.simplifiedChinese: "档位", .traditionalChinese: "檔位", .english: "Mode"],
        "deleteRule": [.simplifiedChinese: "删除规则", .traditionalChinese: "刪除規則", .english: "Delete Rule"],
        "advanced": [.simplifiedChinese: "高级设置", .traditionalChinese: "進階設定", .english: "Advanced"],
        "hysteresis": [.simplifiedChinese: "回落温差", .traditionalChinese: "回落溫差", .english: "Hysteresis"],
        "minimumHold": [.simplifiedChinese: "最短保持时间", .traditionalChinese: "最短保持時間", .english: "Minimum Hold"],
        "samplingInterval": [.simplifiedChinese: "采样间隔", .traditionalChinese: "取樣間隔", .english: "Sampling Interval"],
        "emergencyFull": [.simplifiedChinese: "紧急全速温度", .traditionalChinese: "緊急全速溫度", .english: "Emergency Full Speed"],
        "restoreOnQuit": [.simplifiedChinese: "退出应用时恢复 Apple 自动控制", .traditionalChinese: "結束應用時恢復 Apple 自動控制", .english: "Restore Apple auto control on quit"],
        "restoreAfterWake": [.simplifiedChinese: "睡眠唤醒后恢复自动并重新评估策略", .traditionalChinese: "睡眠喚醒後恢復自動並重新評估策略", .english: "Restore auto and reevaluate after wake"],
        "restoreDailyDefaults": [.simplifiedChinese: "恢复日常办公默认值", .traditionalChinese: "恢復日常辦公預設值", .english: "Restore Daily Defaults"],
        "saveStrategy": [.simplifiedChinese: "保存策略", .traditionalChinese: "儲存策略", .english: "Save Strategy"],
        "seconds": [.simplifiedChinese: "秒", .traditionalChinese: "秒", .english: "sec"]
    ]
}
