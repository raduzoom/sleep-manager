/// One entry from the "Listed by owning process" section of `pmset -g assertions`.
public struct Assertion: Equatable, Sendable {
    public let pid: Int
    public let process: String
    public let type: String
    public let name: String
    public let seconds: Int

    /// What the assertion stops, in plain words.
    public var prevents: String {
        if isDisplaySleep { return "Display sleep" }
        // powerd holds an idle-sleep assertion for as long as the screen is on.
        if name.localizedCaseInsensitiveContains("while display is on") { return "System sleep while display is on" }
        switch type {
        case "PreventUserIdleSystemSleep", "NoIdleSleepAssertion": return "Idle system sleep"
        case "PreventSystemSleep": return "System sleep"
        default: return type
        }
    }

    public var isDisplaySleep: Bool {
        type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion"
    }

    /// `UserIsActive` only means the keyboard or mouse was touched recently, so the menu leaves it out.
    public var isNoise: Bool { type == "UserIsActive" }
}

public enum Assertions {
    private nonisolated(unsafe) static let entry =
        /^\s*pid (\d+)\((.+?)\): \[0x[0-9a-fA-F]+\] (\d+):(\d+):(\d+) (\S+) named: "(.*)"/

    public static func parse(_ output: String) -> [Assertion] {
        var inProcessSection = false
        var result: [Assertion] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("Listed by owning process") {
                inProcessSection = true
                continue
            }
            // Any other unindented line ("Kernel Assertions: ...") ends the section.
            if let first = line.first, !first.isWhitespace {
                inProcessSection = false
                continue
            }
            guard inProcessSection, let m = line.wholeMatch(of: entry) ?? line.prefixMatch(of: entry) else { continue }
            let seconds = Int(m.3)! * 3600 + Int(m.4)! * 60 + Int(m.5)!
            result.append(Assertion(pid: Int(m.1)!, process: String(m.2), type: String(m.6),
                                    name: String(m.7), seconds: seconds))
        }
        return result
    }

    public static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        if minutes > 0 { return "\(minutes) min" }
        return "a few seconds"
    }
}
