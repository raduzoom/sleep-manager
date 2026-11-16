import Foundation

/// The commands behind each menu item. Lid closed mode and Real Sleep go through `sudo -n`, which only
/// works once `scripts/setup.sh` has installed the sudoers rule.
public enum SleepControl {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"

    // Must match the rule in scripts/setup.sh word for word (a test checks this).
    static let realSleepOnArguments = ["-b", "powernap", "0", "tcpkeepalive", "0", "womp", "0"]
    /// Apple's battery defaults.
    static let realSleepOffArguments = ["-b", "powernap", "1", "tcpkeepalive", "1", "womp", "0"]

    /// Whether `SleepDisabled` is set. Nil if `pmset` couldn't be read.
    public static func lidClosedModeIsOn() -> Bool? {
        PowerSettings.sleepDisabled(fromPmsetOutput: Shell.run(pmset, ["-g"]).output)
    }

    /// True when the sudoers rule lets this user switch lid closed mode without a password.
    public static func lidClosedSetupIsDone() -> Bool {
        sudoAllows(["-a", "disablesleep", "1"]) && sudoAllows(["-a", "disablesleep", "0"])
    }

    @discardableResult
    public static func setLidClosedMode(_ on: Bool) -> CommandResult {
        Shell.run(sudo, ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"])
    }

    /// The battery's Power Nap and network wake settings. Nil on a Mac without a battery.
    public static func batteryNetworkWake() -> NetworkWakeSettings? {
        PowerSettings.networkWake(fromPmsetCustomOutput: Shell.run(pmset, ["-g", "custom"]).output)[.battery]
    }

    /// True when the sudoers rule installed by an older setup.sh has been replaced by one that includes Real Sleep.
    public static func realSleepSetupIsDone() -> Bool {
        sudoAllows(realSleepOnArguments) && sudoAllows(realSleepOffArguments)
    }

    /// Success is the exit status alone: turning `tcpkeepalive` off prints a Find My warning but works.
    @discardableResult
    public static func setRealSleep(_ on: Bool) -> CommandResult {
        Shell.run(sudo, ["-n", pmset] + (on ? realSleepOnArguments : realSleepOffArguments))
    }

    /// Reads all of `pmset -g log` (several seconds, megabytes). Never call it on the main thread.
    public static func lastSleepSummary() -> SleepSummary? {
        WakeLog.lastSleep(fromPmsetLog: Shell.run(pmset, ["-g", "log"]).output)
    }

    private static func sudoAllows(_ pmsetArguments: [String]) -> Bool {
        Shell.run(sudo, ["-n", "-l", pmset] + pmsetArguments).succeeded
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
