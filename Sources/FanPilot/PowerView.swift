import Foundation
import IOKit
import SwiftUI

struct PowerReportRow: Identifiable {
    let id = UUID()
    let labelKey: String
    let fallbackLabel: String
    let value: String
    var isSensitive = false
}

struct PowerReportSection: Identifiable {
    let id = UUID()
    let titleKey: String
    let rows: [PowerReportRow]
}

struct PowerReportSnapshot {
    let sections: [PowerReportSection]
    let batteryPercent: Int?
    let chargingState: String
    let health: String
    let cycleCount: Int?
    let chargerWattage: Int?
    let loadedAt: Date
}

final class PowerReportModel: ObservableObject {
    @Published var snapshot: PowerReportSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let snapshot = try PowerReportLoader.load()
                DispatchQueue.main.async {
                    self?.snapshot = snapshot
                    self?.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }
}

enum PowerReportLoader {
    private struct BatteryStatus {
        var source = "--"
        var percent: Int?
        var state = "--"
        var remaining = "--"
    }

    static func load() throws -> PowerReportSnapshot {
        let data = try run("/usr/sbin/system_profiler", arguments: ["SPPowerDataType", "-json"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else {
            throw NSError(domain: "FanPilot.PowerReport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The macOS power report returned an unsupported format."
            ])
        }

        let battery = item(named: "spbattery_information", in: items)
        let model = battery?["sppower_battery_model_info"] as? [String: Any] ?? [:]
        let charge = battery?["sppower_battery_charge_info"] as? [String: Any] ?? [:]
        let health = battery?["sppower_battery_health_info"] as? [String: Any] ?? [:]
        let status = loadBatteryStatus()
        var sections: [PowerReportSection] = []

        appendSection(
            titleKey: "power.modelInformation",
            source: model,
            fields: [
                ("sppower_battery_serial_number", "power.serialNumber", "Serial Number", true),
                ("sppower_battery_manufacturer", "power.manufacturer", "Manufacturer", false),
                ("sppower_battery_device_name", "power.deviceName", "Device Name", false),
                ("sppower_battery_pack_lot_code", "power.packLotCode", "Pack Lot Code", false),
                ("sppower_battery_pcb_lot_code", "power.pcbLotCode", "PCB Lot Code", false),
                ("sppower_battery_firmware_version", "power.firmwareVersion", "Firmware Version", false),
                ("sppower_battery_hardware_revision", "power.hardwareRevision", "Hardware Revision", false),
                ("sppower_battery_cell_revision", "power.cellRevision", "Cell Revision", false)
            ],
            into: &sections
        )

        var chargeRows = rows(
            source: charge,
            fields: [
                ("sppower_battery_at_warn_level", "power.lowWarning", "Below Warning Level", false),
                ("sppower_battery_fully_charged", "power.fullyCharged", "Fully Charged", false),
                ("sppower_battery_is_charging", "power.isCharging", "Charging", false),
                ("sppower_battery_max_capacity", "power.fullChargeCapacity", "Full Charge Capacity (mAh)", false),
                ("sppower_battery_state_of_charge", "power.stateOfCharge", "State of Charge", false)
            ]
        )
        chargeRows.insert(PowerReportRow(labelKey: "power.currentPowerSource", fallbackLabel: "Current Power Source", value: status.source), at: 0)
        if let percent = status.percent {
            chargeRows.insert(PowerReportRow(labelKey: "power.stateOfCharge", fallbackLabel: "State of Charge", value: "\(percent)%"), at: min(1, chargeRows.count))
        }
        chargeRows.insert(PowerReportRow(labelKey: "power.chargeState", fallbackLabel: "Charge State", value: status.state), at: min(2, chargeRows.count))
        if status.remaining != "--" {
            chargeRows.insert(PowerReportRow(labelKey: "power.timeRemaining", fallbackLabel: "Time Remaining", value: status.remaining), at: min(3, chargeRows.count))
        }
        sections.append(PowerReportSection(titleKey: "power.chargeInformation", rows: deduplicated(chargeRows)))

        appendSection(
            titleKey: "power.healthInformation",
            source: health,
            fields: [
                ("sppower_battery_cycle_count", "power.cycleCount", "Cycle Count", false),
                ("sppower_battery_health", "power.condition", "Condition", false)
            ],
            into: &sections
        )

        if let settings = item(named: "sppower_information", in: items) {
            for (key, titleKey) in [("AC Power", "power.acPowerSettings"), ("Battery Power", "power.batteryPowerSettings")] {
                if let values = settings[key] as? [String: Any] {
                    sections.append(PowerReportSection(titleKey: titleKey, rows: settingRows(values)))
                }
            }
        }

        if let hardware = item(named: "sppower_hwconfig_information", in: items) {
            appendSection(
                titleKey: "power.hardwareConfiguration",
                source: hardware,
                fields: [("sppower_ups_installed", "power.upsInstalled", "UPS Installed", false)],
                into: &sections
            )
        }

        var charger = item(named: "sppower_ac_charger_information", in: items) ?? [:]
        let chargerWattage = intValue(charger["sppower_battery_charger_watts"]) ?? loadAdapterWattage()
        if let chargerWattage, charger["sppower_battery_charger_watts"] == nil {
            charger["sppower_battery_charger_watts"] = chargerWattage
        }
        if !charger.isEmpty {
            appendSection(
                titleKey: "power.chargerInformation",
                source: charger,
                fields: [
                    ("sppower_battery_charger_connected", "power.connected", "Connected", false),
                    ("sppower_battery_charger_watts", "power.wattage", "Wattage (W)", false),
                    ("sppower_battery_charger_name", "power.chargerName", "Charger Name", false)
                ],
                into: &sections
            )
        }

        let events = scheduledEventRows(items)
        if !events.isEmpty {
            sections.append(PowerReportSection(titleKey: "power.scheduledEvents", rows: events))
        }

        return PowerReportSnapshot(
            sections: sections.filter { !$0.rows.isEmpty },
            batteryPercent: status.percent,
            chargingState: status.state,
            health: stringValue(health["sppower_battery_health"]) ?? "--",
            cycleCount: intValue(health["sppower_battery_cycle_count"]),
            chargerWattage: chargerWattage,
            loadedAt: Date()
        )
    }

    private static func run(_ path: String, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "FanPilot.PowerReport", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }

    private static func item(named name: String, in items: [[String: Any]]) -> [String: Any]? {
        items.first { $0["_name"] as? String == name }
    }

    private static func appendSection(
        titleKey: String,
        source: [String: Any],
        fields: [(String, String, String, Bool)],
        into sections: inout [PowerReportSection]
    ) {
        let values = rows(source: source, fields: fields)
        if !values.isEmpty {
            sections.append(PowerReportSection(titleKey: titleKey, rows: values))
        }
    }

    private static func rows(source: [String: Any], fields: [(String, String, String, Bool)]) -> [PowerReportRow] {
        fields.compactMap { rawKey, labelKey, fallback, sensitive in
            guard let value = stringValue(source[rawKey]) else { return nil }
            return PowerReportRow(labelKey: labelKey, fallbackLabel: fallback, value: value, isSensitive: sensitive)
        }
    }

    private static func settingRows(_ source: [String: Any]) -> [PowerReportRow] {
        let mappings: [(String, String)] = [
            ("Current Power Source", "power.currentPowerSource"),
            ("System Sleep Timer", "power.systemSleepTimer"),
            ("Disk Sleep Timer", "power.diskSleepTimer"),
            ("Display Sleep Timer", "power.displaySleepTimer"),
            ("Wake On AC Change", "power.wakeOnACChange"),
            ("Wake On Clamshell Open", "power.wakeOnClamshellOpen"),
            ("Wake On LAN", "power.wakeOnLAN"),
            ("Display Sleep Uses Dim", "power.dimBeforeSleep"),
            ("Hibernate Mode", "power.hibernateMode"),
            ("LowPowerMode", "power.lowPowerMode"),
            ("PrioritizeNetworkReachabilityOverSleep", "power.networkPriority")
        ]
        let known = Set(mappings.map(\.0))
        var result = mappings.compactMap { rawKey, labelKey -> PowerReportRow? in
            guard let value = stringValue(source[rawKey]) else { return nil }
            let suffix = rawKey.contains("Timer") ? " min" : ""
            return PowerReportRow(labelKey: labelKey, fallbackLabel: rawKey, value: value + suffix)
        }
        result += source.keys.filter { !known.contains($0) && !$0.hasPrefix("_") }.sorted().compactMap { key in
            guard let value = stringValue(source[key]) else { return nil }
            return PowerReportRow(labelKey: key, fallbackLabel: key, value: value)
        }
        return result
    }

    private static func scheduledEventRows(_ items: [[String: Any]]) -> [PowerReportRow] {
        guard let container = item(named: "sppower_events_info", in: items),
              let groups = container["_items"] as? [[String: Any]] else { return [] }
        let events = groups.flatMap { group -> [[String: Any]] in
            group["_items"] as? [[String: Any]] ?? []
        }
        return events.enumerated().map { index, event in
            let type = stringValue(event["eventtype"]) ?? "event"
            let time = stringValue(event["time"]) ?? "--"
            let owner = stringValue(event["scheduledby"]) ?? "--"
            return PowerReportRow(labelKey: "power.scheduledEvent", fallbackLabel: "Scheduled Event \(index + 1)", value: "\(time) · \(type) · \(owner)")
        }
    }

    private static func loadBatteryStatus() -> BatteryStatus {
        guard let data = try? run("/usr/bin/pmset", arguments: ["-g", "batt"]),
              let output = String(data: data, encoding: .utf8) else { return BatteryStatus() }
        var status = BatteryStatus()
        if let source = output.split(separator: "'").dropFirst().first {
            status.source = String(source)
        }
        if let percentRange = output.range(of: #"\d+%"#, options: .regularExpression) {
            status.percent = Int(output[percentRange].dropLast())
        }
        let details = output.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if details.count > 1 { status.state = details[1] }
        if details.count > 2 { status.remaining = details[2] }
        return status
    }

    private static func loadAdapterWattage() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AdapterDetails" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else { return nil }
        return intValue(value["Watts"])
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: return value
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value)
        default: return nil
        }
    }

    private static func deduplicated(_ rows: [PowerReportRow]) -> [PowerReportRow] {
        var keys = Set<String>()
        return rows.filter { keys.insert($0.labelKey).inserted }
    }
}

struct PowerView: View {
    @ObservedObject var store: FanPilotStore
    @StateObject private var model = PowerReportModel()
    @State private var revealsSensitiveValues = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeader(title: store.text("power"), subtitle: store.text("power.subtitle"))
                    Spacer()
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        model.refresh()
                    } label: {
                        Label(store.text("power.refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }

                if let snapshot = model.snapshot {
                    summary(snapshot)
                    ForEach(snapshot.sections) { section in
                        PowerReportSectionView(
                            store: store,
                            section: section,
                            revealsSensitiveValues: revealsSensitiveValues
                        )
                    }
                    Text("\(store.text("power.updated")) \(snapshot.loadedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if let error = model.errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text(store.text("power.loadFailed"))
                            .font(.headline)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ProgressView(store.text("power.loading"))
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(24)
        }
        .onAppear {
            if model.snapshot == nil { model.refresh() }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    revealsSensitiveValues.toggle()
                } label: {
                    Image(systemName: revealsSensitiveValues ? "eye.slash" : "eye")
                }
                .help(store.text(revealsSensitiveValues ? "power.hideSerial" : "power.showSerial"))
            }
        }
    }

    private func summary(_ snapshot: PowerReportSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            PowerMetricView(title: store.text("power.stateOfCharge"), value: snapshot.batteryPercent.map { "\($0)%" } ?? "--", symbol: "battery.75percent")
            PowerMetricView(title: store.text("power.chargeState"), value: localizedValue(snapshot.chargingState), symbol: "bolt.fill")
            PowerMetricView(title: store.text("power.condition"), value: localizedValue(snapshot.health), symbol: "heart.text.square")
            PowerMetricView(title: store.text("power.cycleCount"), value: snapshot.cycleCount.map(String.init) ?? "--", symbol: "arrow.triangle.2.circlepath")
            PowerMetricView(title: store.text("power.chargingPower"), value: snapshot.chargerWattage.map { "\($0) W" } ?? "--", symbol: "powerplug.fill")
        }
    }

    private func localizedValue(_ value: String) -> String {
        switch value.lowercased() {
        case "true", "yes": return store.text("power.yes")
        case "false", "no": return store.text("power.no")
        case "good", "normal": return store.text("power.normal")
        case "charging": return store.text("power.charging")
        case "charged": return store.text("power.charged")
        case "discharging": return store.text("power.discharging")
        case "ac power": return store.text("power.acPower")
        case "battery power": return store.text("power.batteryPower")
        default: return value
        }
    }
}

private struct PowerMetricView: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PowerReportSectionView: View {
    @ObservedObject var store: FanPilotStore
    let section: PowerReportSection
    let revealsSensitiveValues: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.text(section.titleKey))
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        Text(localizedLabel(row))
                            .foregroundStyle(.secondary)
                            .frame(width: 230, alignment: .leading)
                        Text(displayValue(row))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                    .padding(.vertical, 8)
                    if index < section.rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func localizedLabel(_ row: PowerReportRow) -> String {
        let localized = store.text(row.labelKey)
        return localized == row.labelKey ? row.fallbackLabel : localized
    }

    private func displayValue(_ row: PowerReportRow) -> String {
        if row.isSensitive && !revealsSensitiveValues {
            guard row.value.count > 6 else { return "••••••" }
            return "••••••\(row.value.suffix(4))"
        }
        switch row.value.lowercased() {
        case "true", "yes": return store.text("power.yes")
        case "false", "no": return store.text("power.no")
        case "good", "normal": return store.text("power.normal")
        case "charging": return store.text("power.charging")
        case "charged": return store.text("power.charged")
        case "discharging": return store.text("power.discharging")
        case "ac power": return store.text("power.acPower")
        case "battery power": return store.text("power.batteryPower")
        default: return row.value
        }
    }
}
