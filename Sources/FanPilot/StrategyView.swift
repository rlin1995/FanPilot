import SwiftUI

struct StrategyView: View {
    @ObservedObject var store: FanPilotStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: store.text("strategy"), subtitle: store.text("strategySubtitle"))

                HStack(spacing: 16) {
                    LabeledContent(store.text("strategyName")) {
                        TextField(store.text("strategyName"), text: $store.strategy.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }

                    LabeledContent(store.text("controlSensor")) {
                        Picker("", selection: $store.strategy.controlSensorID) {
                            ForEach(store.sensors) { sensor in
                                Text(sensor.name).tag(sensor.id)
                            }
                        }
                        .frame(width: 260)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(store.text("temperatureRules"))
                            .font(.headline)
                        Spacer()
                        Button {
                            store.addRule()
                        } label: {
                            Label(store.text("addRule"), systemImage: "plus")
                        }
                    }

                    ForEach($store.strategy.rules) { $rule in
                        HStack(spacing: 12) {
                            Text("≥")
                                .foregroundStyle(.secondary)
                            TextField(store.text("temperature"), value: $rule.threshold, formatter: NumberFormatter.temperature)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("°C")
                                .foregroundStyle(.secondary)
                            Picker(store.text("mode"), selection: $rule.mode) {
                                ForEach(CoolingMode.allCases.filter { $0 != .automatic }) { mode in
                                    Text(store.title(for: mode)).tag(mode)
                                }
                            }
                            .frame(width: 130)
                            Spacer()
                            Button(role: .destructive) {
                                store.removeRule(rule)
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
                            Stepper(value: $store.strategy.hysteresis, in: 1...15, step: 1) {
                                Text("\(Int(store.strategy.hysteresis))°C")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text(store.text("minimumHold"))
                            Stepper(value: $store.strategy.minimumHoldSeconds, in: 5...180, step: 5) {
                                Text("\(store.strategy.minimumHoldSeconds) \(store.text("seconds"))")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text(store.text("samplingInterval"))
                            Stepper(value: $store.strategy.samplingIntervalSeconds, in: 1...10, step: 1) {
                                Text("\(Int(store.strategy.samplingIntervalSeconds)) \(store.text("seconds"))")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text(store.text("emergencyFull"))
                            Stepper(value: $store.strategy.emergencyFullSpeedTemperature, in: 85...105, step: 1) {
                                Text("\(Int(store.strategy.emergencyFullSpeedTemperature))°C")
                                    .monospacedDigit()
                            }
                        }
                    }
                    Toggle(store.text("restoreOnQuit"), isOn: $store.strategy.restoreAutomaticOnQuit)
                    Toggle(store.text("restoreAfterWake"), isOn: $store.strategy.restoreAutomaticAfterWake)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button(store.text("restoreDailyDefaults")) {
                        store.setPreset(.daily)
                    }
                    Spacer()
                    Button(store.text("saveStrategy")) {
                        store.setPreset(.custom)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
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
