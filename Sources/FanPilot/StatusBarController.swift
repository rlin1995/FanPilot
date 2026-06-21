import AppKit
import Combine

final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: FanPilotStore
    private weak var windowController: MainWindowController?
    private let contentView = StatusBarContentView(frame: NSRect(x: 0, y: 0, width: 66, height: 24))
    private var cancellables = Set<AnyCancellable>()

    init(store: FanPilotStore, windowController: MainWindowController) {
        self.store = store
        self.windowController = windowController
        configure()
    }

    private func configure() {
        statusItem.length = 66
        statusItem.button?.image = nil
        statusItem.button?.title = ""
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showMenu)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let button = statusItem.button {
            contentView.frame = button.bounds
            contentView.autoresizingMask = [.width, .height]
            button.addSubview(contentView)
        }

        store.$sensors
            .combineLatest(store.$fans, store.$currentStrategyMode, store.$strategy)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.updateTitle()
                self?.statusItem.menu = self?.buildMenu()
            }
            .store(in: &cancellables)
    }

    @objc private func showMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
    }

    private func updateTitle() {
        let temp = Int((store.controlSensor?.temperature ?? store.hottestTemperature).rounded())
        let rpm = store.highestFanRPM
        guard temp > 0, rpm > 0 else {
            contentView.temperatureText = "--°C"
            contentView.rpmText = "--rpm"
            return
        }
        contentView.temperatureText = "\(temp)°C"
        contentView.rpmText = "\(rpm)rpm"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(headerItem("FanPilot"))
        if let sensor = store.controlSensor {
            menu.addItem(headerItem("\(sensor.name)    \(sensor.temperature.temperatureText)"))
        }
        for fan in store.fans {
            menu.addItem(headerItem("\(fan.name)    \(fan.currentRPM) rpm"))
        }
        menu.addItem(.separator())
        menu.addItem(headerItem("当前预设    \(store.selectedPreset.title)"))
        menu.addItem(.separator())

        for mode in CoolingMode.allCases {
            let item = ClosureMenuItem(title: mode.title) { [weak self] in
                self?.store.applyMode(mode)
            }
            item.state = store.currentStrategyMode == mode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "打开 FanPilot") { [weak self] in
            self?.windowController?.show()
        })
        menu.addItem(ClosureMenuItem(title: "恢复 Apple 自动控制") { [weak self] in
            self?.store.restoreAutomaticControl()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "退出") {
            NSApplication.shared.terminate(nil)
        })
        return menu
    }

    private func headerItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

final class StatusBarContentView: NSView {
    var temperatureText = "--°C" {
        didSet { needsDisplay = true }
    }

    var rpmText = "--rpm" {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconSize: CGFloat = 17
        let textX: CGFloat = 23
        let lineHeight: CGFloat = 10
        let centerY = bounds.midY

        let configuration = NSImage.SymbolConfiguration(paletteColors: [.white])
        if let icon = NSImage(systemSymbolName: "fan", accessibilityDescription: "FanPilot")?.withSymbolConfiguration(configuration) {
            icon.draw(
                in: NSRect(
                    x: 2,
                    y: centerY - iconSize / 2,
                    width: iconSize,
                    height: iconSize
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let topLineRect = NSRect(
            x: textX,
            y: centerY,
            width: bounds.width - textX,
            height: lineHeight
        )
        let bottomLineRect = NSRect(
            x: textX,
            y: centerY - lineHeight,
            width: bounds.width - textX,
            height: lineHeight
        )
        temperatureText.draw(in: topLineRect, withAttributes: attributes)
        rpmText.draw(in: bottomLineRect, withAttributes: attributes)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let actionHandler: () -> Void

    init(title: String, keyEquivalent: String = "", actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(title: title, action: #selector(runAction), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        actionHandler()
    }
}
