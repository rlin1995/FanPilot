import SwiftUI

struct StrategyView: View {
    @ObservedObject var store: FanPilotStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "策略", subtitle: "根据一个主控传感器自动切换散热档位")

                HStack(spacing: 16) {
                    LabeledContent("策略名称") {
                        TextField("策略名称", text: $store.strategy.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }

                    LabeledContent("主控传感器") {
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
                        Text("温度规则")
                            .font(.headline)
                        Spacer()
                        Button {
                            store.addRule()
                        } label: {
                            Label("新增规则", systemImage: "plus")
                        }
                    }

                    ForEach($store.strategy.rules) { $rule in
                        HStack(spacing: 12) {
                            Text("≥")
                                .foregroundStyle(.secondary)
                            TextField("温度", value: $rule.threshold, formatter: NumberFormatter.temperature)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("°C")
                                .foregroundStyle(.secondary)
                            Picker("档位", selection: $rule.mode) {
                                ForEach(CoolingMode.allCases.filter { $0 != .automatic }) { mode in
                                    Text(mode.title).tag(mode)
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
                            .help("删除规则")
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("高级设置")
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("回落温差")
                            Stepper(value: $store.strategy.hysteresis, in: 1...15, step: 1) {
                                Text("\(Int(store.strategy.hysteresis))°C")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text("最短保持时间")
                            Stepper(value: $store.strategy.minimumHoldSeconds, in: 5...180, step: 5) {
                                Text("\(store.strategy.minimumHoldSeconds) 秒")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text("采样间隔")
                            Stepper(value: $store.strategy.samplingIntervalSeconds, in: 1...10, step: 1) {
                                Text("\(Int(store.strategy.samplingIntervalSeconds)) 秒")
                                    .monospacedDigit()
                            }
                        }
                        GridRow {
                            Text("紧急全速温度")
                            Stepper(value: $store.strategy.emergencyFullSpeedTemperature, in: 85...105, step: 1) {
                                Text("\(Int(store.strategy.emergencyFullSpeedTemperature))°C")
                                    .monospacedDigit()
                            }
                        }
                    }
                    Toggle("退出应用时恢复 Apple 自动控制", isOn: $store.strategy.restoreAutomaticOnQuit)
                    Toggle("睡眠唤醒后恢复自动并重新评估策略", isOn: $store.strategy.restoreAutomaticAfterWake)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button("恢复日常办公默认值") {
                        store.setPreset(.daily)
                    }
                    Spacer()
                    Button("保存策略") {
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
