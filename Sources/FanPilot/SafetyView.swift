import SwiftUI

struct SafetyView: View {
    @ObservedObject var store: FanPilotStore
    @State private var showsAdvancedDiagnostics = false

    private var needsHelper: Bool {
        store.helperState != .installed && store.smcAccessState == .unavailable && !store.isControlEnabled
    }

    private var hasSMCAccess: Bool {
        store.smcAccessState == .available || store.smcAccessState == .recovering
    }

    private var writeRestricted: Bool {
        store.controlPermissionState == .writeRestricted
    }

    private var statusTitle: String {
        if store.isControlEnabled { return store.text("controlEnabledTitle") }
        if writeRestricted { return store.text("writeRestrictedTitle") }
        if hasSMCAccess { return store.text("smcAvailableTitle") }
        if needsHelper { return store.text("helperNeededTitle") }
        return store.text("monitorOnlyTitle")
    }

    private var statusBody: String {
        if store.isControlEnabled { return store.text("controlEnabledBody") }
        if writeRestricted { return store.text("writeRestrictedBody") }
        if hasSMCAccess { return store.text("smcAvailableBody") }
        if needsHelper { return store.text("helperNeededBody") }
        return store.text("monitorOnlyBody")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: store.text("safety"), subtitle: store.text("safetySubtitle"))

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: store.isControlEnabled ? "checkmark.shield" : writeRestricted ? "exclamationmark.triangle" : needsHelper ? "exclamationmark.shield" : "lock.shield")
                            .font(.largeTitle)
                            .foregroundStyle(store.isControlEnabled ? .green : writeRestricted ? .orange : needsHelper ? .orange : .secondary)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(statusTitle)
                                .font(.title3.weight(.semibold))
                            Text(statusBody)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(store.text("safetyNotice"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if store.isControlEnabled {
                            fittedButton(store.text("restoreAppleAuto")) {
                                store.restoreAutomaticControl()
                            }
                            fittedButton(store.text("uninstallHelper")) {
                                store.uninstallHelper()
                            }
                        } else {
                            fittedButton(store.text("detectAppleSMC")) {
                                store.detectSMC()
                            }
                            fittedButton(store.text("installUpdateHelper")) {
                                store.enableControl()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    DisclosureGroup(isExpanded: $showsAdvancedDiagnostics) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.text("advancedDiagnosticsSubtitle"))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                fittedButton(store.text("runDiagnostics")) {
                                    store.runDiagnostics()
                                }
                                fittedButton(store.text("scanFanKeys")) {
                                    store.runFanKeyDiagnostics()
                                }
                                fittedButton(store.text("testTargetRPM")) {
                                    store.testTargetWrite()
                                }
                            }
                            HStack(spacing: 10) {
                                fittedButton(store.text("testModeKey")) {
                                    store.testModeKeyWrite()
                                }
                                fittedButton(store.text("testMinimumRPM")) {
                                    store.testMinimumWrite()
                                }
                                fittedButton(store.text("testForceControl")) {
                                    store.testForceWrite()
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text(store.text("advancedDiagnostics"))
                            .font(.headline)
                    }
                }
                .padding(18)
                .frame(maxWidth: 760, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                if store.canControlFans {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.text("coolingModes"))
                            .font(.headline)
                        ForEach(CoolingMode.allCases) { mode in
                            HStack(spacing: 12) {
                                if mode == store.currentStrategyMode {
                                    Button(store.title(for: mode)) {
                                        store.applyMode(mode)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .frame(width: 84, alignment: .leading)
                                } else {
                                    Button(store.title(for: mode)) {
                                        store.applyMode(mode)
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(width: 84, alignment: .leading)
                                }
                                Text(store.targetRPMText(for: mode))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 760, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(store.text("status"))
                        .font(.headline)
                    InfoRow(label: store.text("helperStatus"), value: store.helperStatus)
                    InfoRow(label: store.text("smcAccess"), value: store.smcStatus)
                    InfoRow(label: store.text("lastWrite"), value: store.lastWrite)
                    InfoRow(label: store.text("hardwareMode"), value: store.hardwareStatusText)
                }
                .padding(18)
                .frame(maxWidth: 760, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                if !store.diagnosticText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.text("diagnostics"))
                            .font(.headline)
                        ScrollView {
                            Text(store.diagnosticText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(18)
                    .frame(maxWidth: 760, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func fittedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct InfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }
}
