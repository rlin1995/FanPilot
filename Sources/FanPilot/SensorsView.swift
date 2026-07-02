import SwiftUI

struct SensorsView: View {
    @ObservedObject var store: FanPilotStore
    @State private var selectedCategory: SensorCategory = .all
    @State private var searchText = ""

    private var filteredSensors: [TemperatureSensor] {
        store.sensors.filter { sensor in
            let matchesCategory = selectedCategory == .all || sensor.category == selectedCategory
            let matchesSearch = searchText.isEmpty || sensor.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedCategory) {
                ForEach(SensorCategory.allCases) { category in
                    Text(store.title(for: category)).tag(category)
                }
            }
            .frame(width: 160)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: store.text("sensors"), subtitle: store.text("sensorSubtitle"))
                    Spacer()
                    TextField(store.text("search"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                Table(filteredSensors) {
                    TableColumn(store.text("sensorColumn")) { sensor in
                        HStack {
                            Image(systemName: icon(for: sensor.category))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(sensor.name)
                            if sensor.id == store.strategy.controlSensorID {
                                Text(store.text("primary"))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    TableColumn(store.text("temperature")) { sensor in
                        Text(sensor.temperature.temperatureText)
                            .monospacedDigit()
                            .foregroundStyle(temperatureColor(sensor.temperature))
                    }
                    TableColumn(store.text("usage")) { sensor in
                        HStack {
                            Button {
                                store.selectControlSensor(sensor)
                            } label: {
                                Image(systemName: "scope")
                            }
                            .buttonStyle(.borderless)
                            .help("设为主控传感器")

                            Button {
                                store.toggleFavorite(sensor)
                            } label: {
                                Image(systemName: sensor.isFavorite ? "star.fill" : "star")
                            }
                            .buttonStyle(.borderless)
                            .help("收藏到概览")
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func icon(for category: SensorCategory) -> String {
        switch category {
        case .all: return "list.bullet"
        case .cpu: return "cpu"
        case .battery: return "battery.75"
        case .enclosure: return "macbook"
        case .wireless: return "wifi"
        case .storage: return "internaldrive"
        case .other: return "sensor"
        }
    }
}
