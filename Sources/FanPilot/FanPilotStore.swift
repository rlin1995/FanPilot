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
    @Published var language: AppLanguage = .simplifiedChinese
    @Published var helperState: HelperInstallState = .missing
    @Published var smcAccessState: SMCAccessState = .monitorOnly
    @Published var controlPermissionState: ControlPermissionState = .monitorOnly
    @Published private(set) var modifiedPresets: Set<Preset> = []
    @Published private(set) var strategyApplicationPhase: StrategyApplicationPhase = .idle

    private let monitor: HardwareMonitoring
    private let defaults: UserDefaults
    private var timer: Timer?
    private var lastModeChange = Date.distantPast
    private var baselineFansForRestore: [FanReading] = []
    private var savedCustomStrategy: StrategySettings?
    private var presetStrategies: [Preset: StrategySettings] = [:]
    private var strategyFeedbackGeneration = 0

    init(
        monitor: HardwareMonitoring = SMCBackedHardwareMonitor(),
        defaults: UserDefaults = .standard
    ) {
        self.monitor = monitor
        self.defaults = defaults
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
        return "策略：\(sensor.name) \(sensor.temperature.temperatureText) -> \(title(for: currentStrategyMode))"
    }

    var canControlFans: Bool {
        smcAccessState == .available || smcAccessState == .recovering
    }

    var localizer: Localizer {
        Localizer(language: language)
    }

    func text(_ key: String) -> String {
        localizer.text(key)
    }

    func title(for mode: CoolingMode) -> String {
        localizer.text(mode.localizationKey)
    }

    func title(for preset: Preset) -> String {
        localizer.text(preset.localizationKey)
    }

    func displayedTitle(for preset: Preset) -> String {
        if preset == .custom,
           let customName = savedCustomStrategy?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !customName.isEmpty {
            return customName
        }
        return title(for: preset) + (modifiedPresets.contains(preset) ? " *" : "")
    }

    var currentStrategyName: String {
        if selectedPreset == .custom {
            return strategy.name
        }
        return title(for: selectedPreset) + (modifiedPresets.contains(selectedPreset) ? " *" : "")
    }

    var restoreCurrentDefaultsTitle: String {
        String(format: text("restorePresetDefaults"), title(for: selectedPreset))
    }

    var strategyStatusText: String {
        switch strategyApplicationPhase {
        case .idle:
            return isControlEnabled ? text("controlling") : text("monitoring")
        case .switching:
            return text("strategySwitching")
        case .active:
            return text("strategyActive")
        }
    }

    func title(for category: SensorCategory) -> String {
        localizer.text(category.localizationKey)
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: "FanPilot.language")
    }

    func updateSamplingInterval(_ interval: Double) {
        strategy.samplingIntervalSeconds = interval
        save()
        restartTimer()
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
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func prepareForTermination() {
        if strategy.restoreAutomaticOnQuit {
            restoreAutomaticControl()
        } else {
            save()
        }
        stop()
    }

    func handleSystemWake() {
        detectExistingHelper()
        beginStrategyFeedback(for: selectedPreset)
        lastWrite = "系统唤醒，正在重新读取 AppleSMC 并恢复当前策略"
        if strategy.restoreAutomaticAfterWake {
            try? monitor.restoreAutomatic()
            currentStrategyMode = .automatic
            lastModeChange = .distantPast
        }
        strategy = storedStrategy(for: selectedPreset)
        refresh(evaluate: false)
        restartTimer()
        applySelectedStrategyImmediately()
        for delay in [1.0, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.refresh(evaluate: false)
                self.applySelectedStrategyImmediately()
            }
        }
        finishStrategyFeedback(for: selectedPreset)
    }

    func refresh(evaluate: Bool = true) {
        let snapshot = monitor.readSnapshot()
        modelIdentifier = snapshot.modelIdentifier
        hardwareStatusText = snapshot.controlStatusText
        smcAccessState = snapshot.controlAvailable ? .available : .unavailable
        smcStatus = snapshot.controlAvailable ? "AppleSMC 可访问" : "只读/模拟监控"
        if isControlEnabled, !snapshot.controlAvailable {
            isControlEnabled = false
            helperStatus = "需要授权 helper"
            controlPermissionState = .monitorOnly
            lastWrite = "AppleSMC 不可用，已退出控制模式"
        }
        if snapshot.controlAvailable {
            helperStatus = helperStatus.contains("授权") ? helperStatus : "SMC 探测可用"
            helperState = helperStatus.contains("授权") ? .installed : .bundled
            controlPermissionState = isControlEnabled ? .active : .ready
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
        smcAccessState = snapshot.controlAvailable ? .available : .unavailable
        smcStatus = snapshot.controlAvailable ? "AppleSMC 可访问" : "AppleSMC 不可访问"
        sensors = mergeUserSensorState(snapshot.sensors)
        fans = snapshot.fans.map { fan in
            var copy = fan
            copy.mode = currentStrategyMode
            return copy
        }
        if snapshot.controlAvailable {
            helperStatus = "SMC 探测可用"
            helperState = .bundled
            controlPermissionState = isControlEnabled ? .active : .ready
            lastWrite = "AppleSMC 检测成功"
        } else {
            monitor.disableRealHardware()
            isControlEnabled = false
            controlPermissionState = .monitorOnly
            lastWrite = "AppleSMC 检测失败"
        }
    }

    func detectExistingHelper() {
        guard monitor.detectInstalledHelper() else {
            if monitor.hasInstalledHelper() {
                helperState = .attempted
                helperStatus = "已安装旧版 helper，需更新"
                smcAccessState = .unavailable
                controlPermissionState = .monitorOnly
                lastWrite = "检测到旧版 helper，请安装/更新授权 helper"
            }
            return
        }
        helperStatus = "授权 helper 已安装"
        smcStatus = "AppleSMC 检测中"
        helperState = .installed
        smcAccessState = .checking
        controlPermissionState = isControlEnabled ? .active : .ready
        isWriteRestricted = false
        lastWrite = "已检测到本地授权 helper"
    }

    func setPreset(_ preset: Preset) {
        beginStrategyFeedback(for: preset)
        strategy = storedStrategy(for: preset)
        selectedPreset = preset
        save()
        restartTimer()
        applySelectedStrategyImmediately()
        finishStrategyFeedback(for: preset)
    }

    func saveStrategy(_ draft: StrategySettings) {
        let preset = selectedPreset
        beginStrategyFeedback(for: preset)
        var savedStrategy = draft
        savedStrategy.rules.sort { $0.threshold < $1.threshold }
        if preset == .custom {
            let trimmedName = savedStrategy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            savedStrategy.name = trimmedName.isEmpty ? title(for: .custom) : trimmedName
            savedCustomStrategy = savedStrategy
        } else {
            savedStrategy.name = StrategySettings.defaults(for: preset).name
            if savedStrategy.matchesDefaults(for: preset) {
                savedStrategy = StrategySettings.defaults(for: preset)
                presetStrategies.removeValue(forKey: preset)
                modifiedPresets.remove(preset)
            } else {
                presetStrategies[preset] = savedStrategy
                modifiedPresets.insert(preset)
            }
        }
        strategy = savedStrategy
        savePresetLibrary()
        save()
        restartTimer()
        applySelectedStrategyImmediately()
        finishStrategyFeedback(for: preset)
    }

    func restoreCurrentPresetDefaults() {
        let preset = selectedPreset
        beginStrategyFeedback(for: preset)
        let restoredStrategy = StrategySettings.defaults(for: preset)
        if preset == .custom {
            savedCustomStrategy = restoredStrategy
        } else {
            presetStrategies.removeValue(forKey: preset)
            modifiedPresets.remove(preset)
        }
        strategy = restoredStrategy
        savePresetLibrary()
        save()
        restartTimer()
        applySelectedStrategyImmediately()
        finishStrategyFeedback(for: preset)
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
            helperState = .installed
            smcAccessState = .available
            controlPermissionState = .active
            refresh(evaluate: false)
            currentStrategyMode = .automatic
            lastWrite = "授权 helper 已安装；可通过菜单栏或下方档位控制风扇"
            evaluateStrategy(force: true)
        } catch {
            isControlEnabled = false
            helperState = error.localizedDescription.contains("AppleSMC") ? .attempted : .missing
            helperStatus = error.localizedDescription.contains("AppleSMC") ? "helper 已尝试安装" : "未启用"
            smcAccessState = .unavailable
            controlPermissionState = .monitorOnly
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
            smcAccessState = .available
            controlPermissionState = isControlEnabled ? .active : .ready
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
            smcAccessState = .available
            controlPermissionState = isControlEnabled ? .active : .ready
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
            smcAccessState = .available
            lastWrite = "已测试写入 F0Tg/F1Tg（低速）"
            refresh(evaluate: false)
        } catch {
            isWriteRestricted = true
            controlPermissionState = .writeRestricted
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
            smcAccessState = .available
            lastWrite = "已测试写入 F0Tg/F1Tg + FS!（低速）"
            refresh(evaluate: false)
        } catch {
            isWriteRestricted = true
            controlPermissionState = .writeRestricted
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
            helperState = .installed
            smcAccessState = .available
            controlPermissionState = .active
            currentStrategyMode = mode
            manualMode = mode
            lastWrite = "已切换到\(title(for: mode))：\(targetRPMText(for: mode))"
            refresh(evaluate: false)
        } catch {
            isWriteRestricted = true
            controlPermissionState = .writeRestricted
            smcStatus = "AppleSMC 可访问，模式 key 写入失败"
            lastWrite = "\(title(for: mode))写入失败：\(error.localizedDescription)"
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
            smcAccessState = .available
            lastWrite = "已测试写入 F0Mn/F1Mn（低速最低转速）"
            refresh(evaluate: false)
        } catch {
            isWriteRestricted = true
            controlPermissionState = .writeRestricted
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
        helperState = .missing
        smcAccessState = .monitorOnly
        controlPermissionState = .monitorOnly
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
        controlPermissionState = smcAccessState == .available ? .ready : .monitorOnly
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

    private func storedStrategy(for preset: Preset) -> StrategySettings {
        if preset == .custom {
            return savedCustomStrategy ?? StrategySettings.defaults(for: .custom)
        }
        return presetStrategies[preset] ?? StrategySettings.defaults(for: preset)
    }

    private func applySelectedStrategyImmediately() {
        if selectedPreset == .manualFull {
            manualMode = .full
            apply(mode: .full)
            return
        }

        manualMode = .automatic
        apply(mode: .automatic)
        evaluateStrategy(force: true)
    }

    private func beginStrategyFeedback(for preset: Preset) {
        strategyFeedbackGeneration += 1
        strategyApplicationPhase = .switching(preset)
    }

    private func finishStrategyFeedback(for preset: Preset) {
        let generation = strategyFeedbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.strategyFeedbackGeneration == generation else { return }
            self.strategyApplicationPhase = .active(preset)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.strategyFeedbackGeneration == generation else { return }
                self.strategyApplicationPhase = .idle
            }
        }
    }

    private func evaluateStrategy(force: Bool = false) {
        guard manualMode == .automatic, let sensor = controlSensor else { return }
        let nextMode = CoolingStrategyEvaluator.mode(
            for: sensor.temperature,
            rules: strategy.rules,
            currentMode: currentStrategyMode,
            hysteresis: strategy.hysteresis,
            emergencyTemperature: strategy.emergencyFullSpeedTemperature
        )
        let isEmergency = sensor.temperature >= strategy.emergencyFullSpeedTemperature
        let canChange = force
            || isEmergency
            || Date().timeIntervalSince(lastModeChange) >= Double(strategy.minimumHoldSeconds)
        if canChange, nextMode != currentStrategyMode {
            lastModeChange = Date()
            apply(mode: nextMode)
        }
    }

    private func apply(mode: CoolingMode) {
        guard isControlEnabled else {
            currentStrategyMode = mode
            lastWrite = "监控模式：策略建议 \(title(for: mode))，未写入 SMC"
            return
        }
        do {
            if mode == .automatic {
                try monitor.restoreAutomatic()
                currentStrategyMode = .automatic
                lastWrite = "策略回到自动，已交还 Apple 控制"
                isWriteRestricted = false
                controlPermissionState = .active
                smcStatus = "AppleSMC 可访问"
                return
            }
            try monitor.apply(mode: mode, to: fans)
            currentStrategyMode = mode
            lastWrite = "已写入 \(title(for: mode))"
            isWriteRestricted = false
            controlPermissionState = .active
            smcStatus = "AppleSMC 可访问"
        } catch {
            lastWrite = "SMC 写入不可用：\(error.localizedDescription)"
            isControlEnabled = false
            isWriteRestricted = true
            helperStatus = "授权 helper 已安装"
            smcStatus = "AppleSMC 可访问，写入受限"
            controlPermissionState = .writeRestricted
            currentStrategyMode = .automatic
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: strategy.samplingIntervalSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
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
            defaults.set(data, forKey: "FanPilot.strategy")
            if selectedPreset == .custom {
                defaults.set(data, forKey: "FanPilot.customStrategy")
                savedCustomStrategy = strategy
            }
        }
        defaults.set(selectedPreset.rawValue, forKey: "FanPilot.preset")
        defaults.set(isControlEnabled, forKey: "FanPilot.controlEnabled")
    }

    private func savePresetLibrary() {
        let encodedStrategies = Dictionary(
            uniqueKeysWithValues: presetStrategies.map { ($0.key.rawValue, $0.value) }
        )
        if let data = try? JSONEncoder().encode(encodedStrategies) {
            defaults.set(data, forKey: "FanPilot.presetStrategies")
        }
        defaults.set(modifiedPresets.map(\.rawValue), forKey: "FanPilot.modifiedPresets")
    }

    private func load() {
        var loadedStrategy: StrategySettings?
        if let data = defaults.data(forKey: "FanPilot.strategy"),
           let decoded = try? JSONDecoder().decode(StrategySettings.self, from: data) {
            loadedStrategy = decoded
        }
        if let data = defaults.data(forKey: "FanPilot.customStrategy"),
           let decoded = try? JSONDecoder().decode(StrategySettings.self, from: data) {
            savedCustomStrategy = decoded
        }
        if let data = defaults.data(forKey: "FanPilot.presetStrategies"),
           let decoded = try? JSONDecoder().decode([String: StrategySettings].self, from: data) {
            presetStrategies = Dictionary(
                uniqueKeysWithValues: decoded.compactMap { key, value in
                    Preset(rawValue: key).map { ($0, value) }
                }
            )
        }
        let savedModifiedPresets = defaults.stringArray(forKey: "FanPilot.modifiedPresets") ?? []
        modifiedPresets = Set(savedModifiedPresets.compactMap(Preset.init(rawValue:)))
        modifiedPresets.formUnion(presetStrategies.keys)
        if let raw = defaults.string(forKey: "FanPilot.preset"),
           let preset = Preset(rawValue: raw) {
            selectedPreset = preset
        }
        if let raw = defaults.string(forKey: "FanPilot.language"),
           let savedLanguage = AppLanguage(rawValue: raw) {
            language = savedLanguage
        }
        isControlEnabled = defaults.bool(forKey: "FanPilot.controlEnabled")

        if selectedPreset == .custom {
            if savedCustomStrategy == nil {
                savedCustomStrategy = loadedStrategy ?? StrategySettings.defaults(for: .custom)
            }
            strategy = savedCustomStrategy ?? StrategySettings.defaults(for: .custom)
        } else {
            strategy = presetStrategies[selectedPreset] ?? StrategySettings.defaults(for: selectedPreset)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case overview
    case sensors
    case strategy
    case power
    case safety

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .overview: return "overview"
        case .sensors: return "sensors"
        case .strategy: return "strategy"
        case .power: return "power"
        case .safety: return "safety"
        }
    }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .sensors: return "传感器"
        case .strategy: return "策略"
        case .power: return "电源"
        case .safety: return "安全与权限"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "fan"
        case .sensors: return "thermometer.medium"
        case .strategy: return "slider.horizontal.3"
        case .power: return "bolt.batteryblock"
        case .safety: return "lock.shield"
        }
    }
}
