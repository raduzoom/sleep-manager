import AppKit
import SleepCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let keepAwake = KeepAwake()
    private var refreshTimer: Timer?

    // Last known state. Lid closed is always re-read from pmset, never assumed.
    private var lidClosedOn = false
    private var setupDone = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        keepAwake.onStop = { [weak self] in self?.updateIcon() }

        refreshState()
        // Catches changes made from Terminal while the menu is closed.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { self.refreshState() }
        }
    }

    // MARK: State and icon

    private func refreshState() {
        lidClosedOn = SleepControl.lidClosedModeIsOn() ?? lidClosedOn
        setupDone = SleepControl.setupIsDone()
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if lidClosedOn {
            // Not a template, so it stays red on light and dark menu bars.
            button.image = icon("icon-lid-closed", template: false, fallback: "laptopcomputer")
        } else if keepAwake.isOn {
            button.image = icon("icon-keep-awake", template: true, fallback: "laptopcomputer")
        } else {
            button.image = icon("icon-off", template: true, fallback: "moon.zzz")
        }
        button.setAccessibilityLabel(statusText)
    }

    /// Loads one of the Claude Design SVGs from the app bundle. Falls back to an SF Symbol when
    /// running outside the bundle (`swift run`), where there are no resources.
    private func icon(_ name: String, template: Bool, fallback: String) -> NSImage? {
        let image = Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil)
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = template
        return image
    }

    private var statusText: String {
        if lidClosedOn { return "Lid closed mode on: Mac won't sleep" }
        if keepAwake.isOn { return "Keeping awake, screen on" }
        return "Sleeping normally"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshState()
        menu.removeAllItems()

        menu.addItem(disabledItem(statusText))
        menu.addItem(.separator())

        let keepAwakeItem = actionItem("Keep Awake", #selector(toggleKeepAwake))
        keepAwakeItem.state = keepAwake.isOn ? .on : .off
        menu.addItem(keepAwakeItem)

        let lidItem = actionItem("Lid Closed Mode", #selector(toggleLidClosed))
        lidItem.state = lidClosedOn ? .on : .off
        lidItem.isEnabled = setupDone
        if !setupDone {
            lidItem.subtitle = "Setup needed: run setup.sh once"
        }
        menu.addItem(lidItem)

        menu.addItem(.separator())

        let screenItem = actionItem("Turn Screen Off Now", #selector(turnScreenOff))
        if !lidClosedOn && !keepAwake.isOn {
            screenItem.subtitle = "Mac may sleep"
        }
        menu.addItem(screenItem)

        let assertionsItem = NSMenuItem(title: "What's Keeping It Awake", action: nil, keyEquivalent: "")
        assertionsItem.submenu = assertionsMenu()
        menu.addItem(assertionsItem)

        menu.addItem(.separator())
        let quitItem = actionItem("Quit Sleep Manager", #selector(quit))
        quitItem.keyEquivalent = "q"
        if lidClosedOn {
            quitItem.subtitle = "Lid Closed Mode stays on"
        }
        menu.addItem(quitItem)
    }

    private func assertionsMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let assertions = SleepControl.currentAssertions()
            .filter { !$0.isNoise }
            .sorted { $0.seconds > $1.seconds }
        if assertions.isEmpty {
            submenu.addItem(disabledItem("Nothing is keeping it awake"))
        }
        for assertion in assertions {
            let item = disabledItem(assertion.process)
            item.subtitle = "\(assertion.prevents) · \(Assertions.formatDuration(seconds: assertion.seconds))"
            item.toolTip = assertion.name
            item.image = NSImage(systemSymbolName: assertion.isDisplaySleep ? "display" : "moon",
                                 accessibilityDescription: assertion.prevents)
            submenu.addItem(item)
        }
        return submenu
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Actions

    @objc private func toggleKeepAwake() {
        if keepAwake.isOn {
            keepAwake.stop()
        } else {
            do {
                try keepAwake.start()
            } catch {
                showError("Couldn't start caffeinate", error.localizedDescription)
            }
        }
        updateIcon()
    }

    @objc private func toggleLidClosed() {
        let result = SleepControl.setLidClosedMode(!lidClosedOn)
        if !result.succeeded {
            showError("Couldn't change lid closed mode", result.output)
        }
        refreshState()
    }

    @objc private func turnScreenOff() {
        SleepControl.turnScreenOffNow()
    }

    @objc private func quit() {
        // Keep awake ends with the app; lid closed mode stays as it is on purpose.
        keepAwake.stop()
        NSApp.terminate(nil)
    }

    private func showError(_ message: String, _ details: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.runModal()
    }
}
