import Combine
import Foundation

final class FanPilotStore: ObservableObject {
    @Published var selectedPreset: Preset = .daily
    @Published var manualMode: CoolingMode = .automatic
    @Published var sensors: [TemperatureSensor] = []
    @Published var fans: [FanReading] = []
    @Published var strategy = StrategySettings()
    @Published var selectedTab: AppTab = .overview
    @Published var modelIdentifier = "MacBook"
    @Published var isControlEnabled = false
    @Published var helperStatus = "未安装"
    @Published var smcStatus = "只读监控"
    @Published var lastWrite = "尚未写入"
    @Published var diagnosticText = ""
    @Published var currentStrategyMode: CoolingMode = .automatic
    @Published var hardwareStatusText = "启动中"
    @Published var isWriteRestricted = false

    private let monitor: HardwareMonitoring
    private var timer: Timer?
    private var lastModeChange = Date.distantPast
    private var baselineFansForRestore: [FanReading] = []

    init(monitor: HardwareMonitoring = SMCBackedHardwareMonitor()) {
        self.monitor = monitor
        load()
    }

    var controlSensor: TemperatureSensor? {
        sensors.first { $0.id == strategy.controlSensorID } ?? sensors.first
    }

    var hottestTemperature: Double {
        sensors.map(\.temperature).max() ?? 0
    }

    var highestFanRPM: Int {
        fans.map(\.currentRPM).max() ?? 0
    }

    var activeRuleText: String {
        guard let sensor = controlSensor else { return "等待传感器数据" }
        return "策略：\(sensor.name) \(sensor.temperature.temperatureText) -> \(currentStrategyMode.title)"
    }

    var canControlFans: Bool {
        smcStatus.contains("AppleSMC 可访问") || hardwareStatusText.contains("AppleSMC 监控")
    }

    func targetRPMText(for mode: CoolingMode) -> String {
        guard mode != .automatic, !fans.isEmpty else {
            return mode.detail
        }
        let values = fans.map { fan -> String in
            let span = max(0, fan.maximumRPM - fan.minimumRPM)
            let target = fan.minimumRPM + Int(Double(span) * mode.rpmRatio)
            return "\(fan.name) \(min(fan.maximumRPM, max(fan.minimumRPM, target)))rpm"
        }
        return values.joined(separator: " / ")
    }

    func start() {
        detectExistingHelper()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: strategy.samplingIntervalSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func handleSystemWake() {
        detectExistingHelper()
        lastWrite = "系统唤醒，正在重新读取 AppleSMC"
        refresh(evaluate: false)
        for delay in [1.0, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh(evaluate: false)
            }
        }
    }

    func refresh(evaluate: Bool = true) {
        let snapshot = monitor.readSnapshot()
        modelIdentifier = snapshot.modelIdentifier
        hardwareStatusText = snapshot.controlStatusText
        smcStatus = snapshot.controlAvailable ? "AppleSMC 可访问" : "只读/模拟监控"
        if isControlEnabled, !snapshot.controlAvailable {
            isControlEnabled = false
            helperStatus = "需要授权 helper"
            lastWrite = "AppleSMC 不可用，已退出控制模式"
        }
        if snapshot.controlAvailable {
            helperStatus = helperStatus.contains("授权") ? helperStatus : "SMC 探测可用"
        }
        sensors = mergeUserSensorState(snapshot.sensors)
        fans = snapshot.fans.map { fan in
            var copy = fan
            copy.mode = currentStrategyMode
            return copy
        }
        if evaluate {
            evaluateStrategy()
        }
    }

    func detectSMC() {
        monitor.useRealHardware()
        let snapshot = monitor.readSnapshot()
        modelIdentifier = snapshot.modelIdentifier
        hardwareStatusText = snapshot.controlStatusText
        smcStatus = snapshot.controlAvailable ? "AppleSMC 可访问" : "AppleSMC 不可访问"
        sensors = mergeUserSensorState(snapshot.sensors)
        fans = snapshot.fans.map { fan in
            var copy = fan
            copy.mode = currentStrategyMode
            return copy
        }
        if snapshot.controlAvailable {
            helperStatus = "SMC 探测可用"
            lastWrite = "AppleSMC 检测成功"
        } else {
            monitor.disableRealHardware()
            isControlEnabled = false
            lastWrite = "AppleSMC 检测失败"
        }
    }

    func detectExistingHelper() {
        guard monitor.detectInstalledHelper() else { return }
        helperStatus = "授权 helper 已安装"
        smcStatus = "AppleSMC 检测中"
        isControlEnabled = true
        isWriteRestricted = false
        lastWrite = "已检测到本地授权 helper"
    }

    func setPreset(_ preset: Preset) {
        selectedPreset = preset
        switch preset {
        case .daily:
            strategy.name = "日常办公"
            strategy.rules = [
                CoolingRule(threshold: 70, mode: .low),
                CoolingRule(threshold: 82, mode: .medium),
                CoolingRule(threshold: 92, mode: .high)
            ]
        case .externalDisplay:
            strategy.name = "外接显示器"
            strategy.rules = [
                CoolingRule(threshold: 65, mode: .low),
                CoolingRule(threshold: 76, mode: .medium),
                CoolingRule(threshold: 86, mode: .high),
                CoolingRule(threshold: 94, mode: .full)
            ]
        case .heavyLoad:
            strategy.name = "高负载"
            strategy.rules = [
                CoolingRule(threshold: 60, mode: .low),
                CoolingRule(threshold: 72, mode: .medium),
                CoolingRule(threshold: 82, mode: .high),
                CoolingRule(threshold: 90, mode: .full)
            ]
        case .manualFull:
            manualMode = .full
            apply(mode: .full)
        case .custom:
            strategy.name = "自定义"
        }
        save()
        evaluateStrategy(force: true)
    }

    func setManualMode(_ mode: CoolingMode) {
        manualMode = mode
        if mode == .automatic {
            restoreAutomaticControl()
        } else {
            apply(mode: mode)
        }
    }

    func enableControl() {
        do {
            monitor.useRealHardware()
            helperStatus = try monitor.prepareControl()
            smcStatus = "AppleSMC 可访问"
            isControlEnabled = true
            isWriteRestricted = false
            refresh(evaluate: false)
            currentStrategyMode = .automatic
            lastWrite = "授权 helper 已安装；可通过菜单栏或下方档位控制风扇"
            evaluateStrategy(force: true)
        } catch {
            isControlEnabled = false
            helperStatus = error.localizedDescription.contains("AppleSMC") ? "helper 已尝试安装" : "未启用"
            smcStatus = error.localizedDescription
            lastWrite = "启用失败：\(error.localizedDescription)"
            monitor.disableRealHardware()
        }
        save()
    }

    func runDiagnostics() {
        do {
            diagnosticText = try monitor.diagnose()
            helperStatus = "SMC 探测可用"
            smcStatus = "AppleSMC 可访问"
            isWriteRestricted = false
            lastWrite = "SMC 诊断完成"
        } catch {
            diagnosticText = error.localizedDescription
            lastWrite = "SMC 诊断失败"
        }
    }

    func runFanKeyDiagnostics() {
        do {
            diagnosticText = try monitor.fanKeys()
            helperStatus = "SMC 探测可用"
            smcStatus = "AppleSMC 可访问"
            lastWrite = "风扇 key 诊断完成"
        } catch {
            diagnosticText = error.localizedDescription
            lastWrite = "风扇 key 诊断失败"
        }
    }

    func testTargetWrite() {
        do {
            guard !fans.isEmpty else {
                throw HardwareControlError.smc("未检测到风扇")
            }
            try monitor.testWrite(mode: .low, fans: fans, useForceMask: false)
            isWriteRestricted = false
            helperStatus = "授权 helper 已安装"
            smcStatus = "AppleSMC 可访问，目标转速写入成功"
            lastWrite = "已测试写入 F0Tg/F1Tg（低速）"
            refresh(evaluate: false)
        } catch {
            isWriteRestricted = true
            smcStatus = "AppleSMC 可访问，目标转速写入失败"
            lastWrite = "目标转速写入失败：\(error.localizedDescription)"
        }
    }

    func testForceWrite() {
        do {
            guard !fans.isEmpty else {
                throw HardwareControlError.smc("未检测到风扇")
            }
            try monitor.testWrite(mode: .low, fans: fans, useForceMask: true)
            isWriteRestricted = false
            helperStatus = "授权 helper 已安装"
            smcStatus = "AppleSMC 可访问，强制控制写入成功"
            lastWrite = "已测试写入 F0Tg/F1Tg + FS!（低速）"
            refresh(evaluate: false)
        } catch {
            isWriteRestricted = true
            smcStatus = "AppleSMC 可访问，强制控制写入失败"
            lastWrite = "强制控制写入失败：\(error.localizedDescription)"
        }
    }

    func testModeKeyWrite() {
        applyMode(.low)
    }

    func applyMode(_ mode: CoolingMode) {
        do {
            if mode == .automatic {
                restoreAutomaticControl()
                return
            }
            guard !fans.isEmpty else {
                throw HardwareControlError.smc("未检测到风扇")
            }
            try monitor.testModeKeyWrite(mode: mode, fans: fans)
            isWriteRestricted = false
            isControlEnabled = true
            helperStatus = "授权 helper 已安装"
            smcStatus = "AppleSMC 可访问，模式 key 写入成功"
            currentStrategyMode = mode
            manualMode = mode
            lastWrite = "已切换到\(mode.title)：\(targetRPMText(for: mode))"
            refresh(evaluate: false)
        } catch {
            isWriteRestricted = true
            smcStatus = "AppleSMC 可访问，模式 key 写入失败"
            lastWrite = "\(mode.title)写入失败：\(error.localizedDescription)"
        }
    }

    func testMinimumWrite() {
        do {
            guard !fans.isEmpty else {
                throw HardwareControlError.smc("未检测到风扇")
            }
            if baselineFansForRestore.isEmpty {
                baselineFansForRestore = fans
            }
            try monitor.testMinimumWrite(mode: .low, fans: baselineFansForRestore)
            isWriteRestricted = false
            helperStatus = "授权 helper 已安装"
            smcStatus = "AppleSMC 可访问，最低转速写入成功"
            lastWrite = "已测试写入 F0Mn/F1Mn（低速最低转速）"
            refresh(evaluate: false)
        } catch {
            isWriteRestricted = true
            smcStatus = "AppleSMC 可访问，最低转速写入失败"
            lastWrite = "最低转速写入失败：\(error.localizedDescription)"
        }
    }

    func uninstallHelper() {
        do {
            try monitor.uninstallHelper()
        } catch {
            lastWrite = "卸载 helper 失败：\(error.localizedDescription)"
        }
        isControlEnabled = false
        isWriteRestricted = false
        helperStatus = "未安装"
        smcStatus = "只读监控"
        if !lastWrite.contains("卸载 helper 失败") {
            lastWrite = "尚未写入"
        }
        restoreAutomaticControl()
        save()
    }

    func restoreAutomaticControl() {
        if !baselineFansForRestore.isEmpty {
            try? monitor.restoreMinimums(fans: baselineFansForRestore)
            baselineFansForRestore = []
        }
        currentStrategyMode = .automatic
        manualMode = .automatic
        try? monitor.restoreAutomatic()
        isControlEnabled = false
        isWriteRestricted = false
        lastWrite = "已恢复 Apple 自动控制"
        save()
        refresh(evaluate: false)
    }

    func toggleFavorite(_ sensor: TemperatureSensor) {
        guard let index = sensors.firstIndex(where: { $0.id == sensor.id }) else { return }
        sensors[index].isFavorite.toggle()
    }

    func selectControlSensor(_ sensor: TemperatureSensor) {
        var updatedStrategy = strategy
        updatedStrategy.controlSensorID = sensor.id
        strategy = updatedStrategy
        save()
        evaluateStrategy(force: true)
    }

    func addRule() {
        strategy.rules.append(CoolingRule(threshold: 75, mode: .medium))
        strategy.rules.sort { $0.threshold < $1.threshold }
        selectedPreset = .custom
    }

    func removeRule(_ rule: CoolingRule) {
        strategy.rules.removeAll { $0.id == rule.id }
        selectedPreset = .custom
    }

    private func evaluateStrategy(force: Bool = false) {
        guard manualMode == .automatic, let sensor = controlSensor else { return }
        let nextMode: CoolingMode
        if sensor.temperature >= strategy.emergencyFullSpeedTemperature {
            nextMode = .full
        } else {
            nextMode = strategy.rules
                .sorted { $0.threshold < $1.threshold }
                .last { sensor.temperature >= $0.threshold }?
                .mode ?? .automatic
        }
        let canChange = force || Date().timeIntervalSince(lastModeChange) >= Double(strategy.minimumHoldSeconds)
        if canChange, nextMode != currentStrategyMode {
            lastModeChange = Date()
            apply(mode: nextMode)
        }
    }

    private func apply(mode: CoolingMode) {
        guard isControlEnabled else {
            lastWrite = "监控模式：策略建议 \(mode.title)，未写入 SMC"
            return
        }
        do {
            if mode == .automatic {
                try monitor.restoreAutomatic()
                currentStrategyMode = .automatic
                lastWrite = "策略回到自动，已交还 Apple 控制"
                isWriteRestricted = false
                smcStatus = "AppleSMC 可访问"
                return
            }
            try monitor.apply(mode: mode, to: fans)
            currentStrategyMode = mode
            lastWrite = "已写入 \(mode.title)"
            isWriteRestricted = false
            smcStatus = "AppleSMC 可访问"
        } catch {
            lastWrite = "SMC 写入不可用：\(error.localizedDescription)"
            isControlEnabled = false
            isWriteRestricted = true
            helperStatus = "授权 helper 已安装"
            smcStatus = "AppleSMC 可访问，写入受限"
            currentStrategyMode = .automatic
        }
    }

    private func mergeUserSensorState(_ incoming: [TemperatureSensor]) -> [TemperatureSensor] {
        incoming.map { sensor in
            var copy = sensor
            if let old = sensors.first(where: { $0.id == sensor.id }) {
                copy.isFavorite = old.isFavorite
            }
            return copy
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(strategy) {
            UserDefaults.standard.set(data, forKey: "FanPilot.strategy")
        }
        UserDefaults.standard.set(selectedPreset.rawValue, forKey: "FanPilot.preset")
        UserDefaults.standard.set(isControlEnabled, forKey: "FanPilot.controlEnabled")
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "FanPilot.strategy"),
           let decoded = try? JSONDecoder().decode(StrategySettings.self, from: data) {
            strategy = decoded
        }
        if let raw = UserDefaults.standard.string(forKey: "FanPilot.preset"),
           let preset = Preset(rawValue: raw) {
            selectedPreset = preset
        }
        isControlEnabled = UserDefaults.standard.bool(forKey: "FanPilot.controlEnabled")
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case overview
    case sensors
    case strategy
    case safety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .sensors: "传感器"
        case .strategy: "策略"
        case .safety: "安全与权限"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "fan"
        case .sensors: "thermometer.medium"
        case .strategy: "slider.horizontal.3"
        case .safety: "lock.shield"
        }
    }
}
