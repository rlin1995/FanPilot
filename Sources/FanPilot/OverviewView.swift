import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: FanPilotStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "风扇", subtitle: "最低 / 当前 / 最大 RPM")
                    ForEach(store.fans) { fan in
                        FanRow(fan: fan)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "关键温度", subtitle: store.hardwareStatusText)
                    if let sensor = store.controlSensor {
                        ControlSensorCard(sensor: sensor)
                    }
                    ForEach(store.sensors.filter(\.isFavorite).prefix(6)) { sensor in
                        SensorCompactRow(sensor: sensor)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 360, alignment: .topLeading)
            }
            .padding(24)

            Divider()
            HStack {
                Text(store.activeRuleText)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("采样间隔：\(Int(store.strategy.samplingIntervalSeconds)) 秒")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
}

struct FanRow: View {
    var fan: FanReading

    private var progress: Double {
        let span = max(1, fan.maximumRPM - fan.minimumRPM)
        return min(1, max(0, Double(fan.currentRPM - fan.minimumRPM) / Double(span)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "fan")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fan.name)
                        .font(.headline)
                    Text("\(fan.minimumRPM) / \(fan.currentRPM) / \(fan.maximumRPM) rpm")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(fan.mode.title)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ControlSensorCard: View {
    var sensor: TemperatureSensor

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("主控传感器")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sensor.name)
                    .font(.headline)
            }
            Spacer()
            Text(sensor.temperature.temperatureText)
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(temperatureColor(sensor.temperature))
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SensorCompactRow: View {
    var sensor: TemperatureSensor

    var body: some View {
        HStack {
            Text(sensor.name)
            Spacer()
            Text(sensor.temperature.temperatureText)
                .monospacedDigit()
                .foregroundStyle(temperatureColor(sensor.temperature))
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}
