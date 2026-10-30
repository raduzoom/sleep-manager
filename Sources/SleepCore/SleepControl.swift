import Foundation

/// The commands behind each menu item. Lid closed mode goes through `sudo -n`, which only
/// works once `scripts/setup.sh` has installed the sudoers rule.
public enum SleepControl {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"

    /// Whether `SleepDisabled` is set. Nil if `pmset` couldn't be read.
    public static func lidClosedModeIsOn() -> Bool? {
        PowerSettings.sleepDisabled(fromPmsetOutput: Shell.run(pmset, ["-g"]).output)
    }

    /// True when the sudoers rule lets this user switch lid closed mode without a password.
    public static func setupIsDone() -> Bool {
        Shell.run(sudo, ["-n", "-l", pmset, "-a", "disablesleep", "1"]).succeeded
            && Shell.run(sudo, ["-n", "-l", pmset, "-a", "disablesleep", "0"]).succeeded
    }

    @discardableResult
    public static func setLidClosedMode(_ on: Bool) -> CommandResult {
        Shell.run(sudo, ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"])
    }

    public static func turnScreenOffNow() {
        Shell.run(pmset, ["displaysleepnow"])
    }

    public static func currentAssertions() -> [Assertion] {
        Assertions.parse(Shell.run(pmset, ["-g", "assertions"]).output)
    }
}

/// Keep awake mode: a `caffeinate -d` child that also exits when this app exits.
@MainActor
public final class KeepAwake {
    private var process: Process?
    /// Called on the main actor when caffeinate stops for any reason.
    public var onStop: (() -> Void)?

    public init() {}

    public var isOn: Bool { process?.isRunning ?? false }

    public func start() throws {
        guard !isOn else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.process = nil
                self?.onStop?()
            }
        }
        try process.run()
        self.process = process
    }

    public func stop() {
        process?.terminate()
        process = nil
    }
}
