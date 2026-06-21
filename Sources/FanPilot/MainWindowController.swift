import AppKit
import SwiftUI

final class MainWindowController: NSWindowController {
    private let store: FanPilotStore

    init(store: FanPilotStore) {
        self.store = store
        let contentView = FanPilotRootView(store: store)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "FanPilot"
        window.miniwindowImage = NSApplication.shared.applicationIconImage
        window.setContentSize(NSSize(width: 1040, height: 680))
        window.minSize = NSSize(width: 920, height: 600)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct FanPilotRootView: View {
    @ObservedObject var store: FanPilotStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                        .tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                Group {
                    switch store.selectedTab {
                    case .overview:
                        OverviewView(store: store)
                    case .sensors:
                        SensorsView(store: store)
                    case .strategy:
                        StrategyView(store: store)
                    case .safety:
                        SafetyView(store: store)
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FanPilot")
                    .font(.title2.weight(.semibold))
                Text(store.modelIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("当前预设", selection: Binding(
                get: { store.selectedPreset },
                set: { store.setPreset($0) }
            )) {
                ForEach(Preset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .frame(width: 150)
            StatusPill(text: store.isControlEnabled ? "控制中" : "监控中", color: store.isControlEnabled ? .green : .blue)
            Button {
                store.restoreAutomaticControl()
            } label: {
                Label("恢复自动", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

struct StatusPill: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }
}
