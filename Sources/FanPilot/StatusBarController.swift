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

        store.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
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
        contentView.temperatureText = temp > 0 ? "\(temp)°C" : "--°C"
        contentView.rpmText = rpm >= 0 && !store.fans.isEmpty ? "\(rpm)rpm" : "--rpm"
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
        menu.addItem(headerItem("\(store.text("currentPresetMenu"))    \(store.displayedTitle(for: store.selectedPreset))"))
        menu.addItem(.separator())

        menu.addItem(manualModeMenuItem())
        menu.addItem(strategyMenuItem())

        menu.addItem(.separator())
        let languageItem = NSMenuItem(title: store.text("language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = ClosureMenuItem(title: language.nativeTitle) { [weak self] in
                self?.store.setLanguage(language)
                self?.statusItem.menu = self?.buildMenu()
            }
            item.state = store.language == language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: store.text("openFanPilot")) { [weak self] in
            self?.windowController?.show()
        })
        menu.addItem(ClosureMenuItem(title: store.text("restoreAppleAuto")) { [weak self] in
            self?.store.restoreAutomaticControl()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: store.text("quit")) {
            NSApplication.shared.terminate(nil)
        })
        return menu
    }

    private func manualModeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: store.text("manualModeMenu"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in CoolingMode.allCases {
            let modeItem = ClosureMenuItem(title: store.title(for: mode)) { [weak self] in
                self?.store.applyMode(mode)
            }
            modeItem.state = store.currentStrategyMode == mode ? .on : .off
            submenu.addItem(modeItem)
        }
        item.submenu = submenu
        return item
    }

    private func strategyMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: store.text("strategy"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(headerItem("\(store.text("currentStrategyMenu"))    \(store.displayedTitle(for: store.selectedPreset))"))
        submenu.addItem(.separator())
        for preset in Preset.allCases {
            let presetItem = ClosureMenuItem(title: store.displayedTitle(for: preset)) { [weak self] in
                self?.store.setPreset(preset)
            }
            presetItem.state = store.selectedPreset == preset ? .on : .off
            submenu.addItem(presetItem)
        }
        item.submenu = submenu
        return item
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconSize: CGFloat = 17
        let textX: CGFloat = 23
        let lineHeight: CGFloat = 10
        let centerY = bounds.midY

        let foregroundColor = NSColor.labelColor
        let configuration = NSImage.SymbolConfiguration(paletteColors: [foregroundColor])
        let icon = NSImage(systemSymbolName: "fan", accessibilityDescription: "FanPilot")
            ?? NSImage(systemSymbolName: "fanblades", accessibilityDescription: "FanPilot")
        if let icon = icon?.withSymbolConfiguration(configuration) {
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
        } else {
            drawFallbackFan(
                in: NSRect(
                    x: 2,
                    y: centerY - iconSize / 2,
                    width: iconSize,
                    height: iconSize
                ),
                color: foregroundColor
            )
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: foregroundColor
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

    private func drawFallbackFan(in rect: NSRect, color: NSColor) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.43

        color.setFill()
        for index in 0..<3 {
            let angle = CGFloat(index) * 2 * .pi / 3
            let path = NSBezierPath()
            path.move(to: center)
            path.curve(
                to: NSPoint(
                    x: center.x + cos(angle + 0.82) * radius,
                    y: center.y + sin(angle + 0.82) * radius
                ),
                controlPoint1: NSPoint(
                    x: center.x + cos(angle + 0.15) * radius * 0.38,
                    y: center.y + sin(angle + 0.15) * radius * 0.38
                ),
                controlPoint2: NSPoint(
                    x: center.x + cos(angle + 0.46) * radius,
                    y: center.y + sin(angle + 0.46) * radius
                )
            )
            path.curve(
                to: center,
                controlPoint1: NSPoint(
                    x: center.x + cos(angle + 1.18) * radius * 0.82,
                    y: center.y + sin(angle + 1.18) * radius * 0.82
                ),
                controlPoint2: NSPoint(
                    x: center.x + cos(angle + 1.42) * radius * 0.22,
                    y: center.y + sin(angle + 1.42) * radius * 0.22
                )
            )
            path.close()
            path.fill()
        }

        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius * 0.16,
                y: center.y - radius * 0.16,
                width: radius * 0.32,
                height: radius * 0.32
            )
        ).fill()
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
