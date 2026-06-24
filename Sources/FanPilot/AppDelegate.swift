import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FanPilotStore()
    private var windowController: MainWindowController?
    private var statusBarController: StatusBarController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyApplicationIcon()
        observeSystemWake()

        let controller = MainWindowController(store: store)
        windowController = controller
        statusBarController = StatusBarController(store: store, windowController: controller)

        store.start()
        controller.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.prepareForTermination()
    }

    private func applyApplicationIcon() {
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png")
        guard let iconURL, let icon = NSImage(contentsOf: iconURL) else {
            return
        }
        NSApplication.shared.applicationIconImage = icon
    }

    private func observeSystemWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemDidWake() {
        store.handleSystemWake()
    }
}
