import SwiftUI

struct StrategyView: View {
    @ObservedObject var store: FanPilotStore
    @State private var draft: StrategySettings
    @State private var didSave = false

    init(store: FanPilotStore) {
        self.store = store
        _draft = State(initialValue: store.strategy)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: store.text("strategy"), subtitle: store.text("strategySubtitle"))

                HStack(spacing: 16) {
                    LabeledContent(store.text("strategyName")) {
                        if store.selectedPreset == .custom {
                            TextField(store.text("strategyName"), text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        } else {
                            TextField(
                                store.text("strategyName"),
                                text: .constant(store.currentStrategyName)
                            )
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                            .frame(width: 220)
                            .help(store.text("presetNameLocked"))
                        }
                    }

                    LabeledContent(store.text("controlSensor")) {
                        Picker("", selection: $draft.controlSensorID) {
                            ForEach(store.sensors) { sensor in
                                Text(sensor.name).tag(sensor.id)
                            }
                        }
                        .frame(width: 260)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.text("temperatureRules"))
                                .font(.headline)
                            Text(store.text("temperatureRulesHint"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            draft.rules.append(CoolingRule(threshold: 75, mode: .medium))
                        } label: {
                            Label(store.text("addRule"), systemImage: "plus")
                        }
                    }

                    ForEach($draft.rules) { $rule in
                        HStack(spacing: 12) {
                            Text("≥")
                                .foregroundStyle(.secondary)
                            TextField(store.text("temperature"), value: $rule.threshold, formatter: NumberFormatter.temperature)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("°C")
                                .foregroundStyle(.secondary)
                            Picker(store.text("mode"), selection: $rule.mode) {
                                ForEach(CoolingMode.allCases) { mode in
                                    Text(store.title(for: mode)).tag(mode)
                                }
                            }
                            .frame(width: 130)
                            Spacer()
                            Button(role: .destructive) {
                                draft.rules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(store.text("deleteRule"))
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(store.text("advanced"))
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text(store.text("hysteresis"))
                            Stepper(value: $draft.hysteresis, in: 1...15, step: 1) {
                                Text("\(Int(draft.hysteresis))°C")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text(store.text("minimumHold"))
                            Stepper(value: $draft.minimumHoldSeconds, in: 5...180, step: 5) {
                                Text("\(draft.minimumHoldSeconds) \(store.text("seconds"))")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text(store.text("samplingInterval"))
                            Stepper(value: $draft.samplingIntervalSeconds, in: 1...10, step: 1) {
                                Text("\(Int(draft.samplingIntervalSeconds)) \(store.text("seconds"))")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text(store.text("emergencyFull"))
                            Stepper(value: $draft.emergencyFullSpeedTemperature, in: 85...105, step: 1) {
                                Text("\(Int(draft.emergencyFullSpeedTemperature))°C")
                                    .monospacedDigit()
                            }
                        }
                    }
                    Toggle(store.text("restoreOnQuit"), isOn: $draft.restoreAutomaticOnQuit)
                    Toggle(store.text("restoreAfterWake"), isOn: $draft.restoreAutomaticAfterWake)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button(store.restoreCurrentDefaultsTitle) {
                        store.restoreCurrentPresetDefaults()
                        draft = store.strategy
                        didSave = false
                    }
                    Spacer()
                    Button {
                        store.saveStrategy(draft)
                        draft = store.strategy
                        didSave = true
                    } label: {
                        Label(
                            store.text(didSave ? "strategySaved" : "saveStrategy"),
                            systemImage: didSave ? "checkmark" : "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .onAppear {
            draft = store.strategy
        }
        .onChange(of: store.selectedPreset) { _ in
            draft = store.strategy
            didSave = false
        }
        .onChange(of: draft) { _ in
            didSave = false
        }
    }
}

extension NumberFormatter {
    static var temperature: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }
}
