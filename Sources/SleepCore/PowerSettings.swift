public enum PowerSettings {
    /// Reads `SleepDisabled` from `pmset -g` output. Nil when the line is missing.
    public static func sleepDisabled(fromPmsetOutput output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "SleepDisabled" {
                return fields[1] == "1"
            }
        }
        return nil
    }
}

/// A section of `pmset -g custom`.
public enum PowerSource: String, Sendable {
    case battery = "Battery Power"
    case ac = "AC Power"
}

/// The three settings that let network traffic and Power Nap wake a sleeping Mac.
public struct NetworkWakeSettings: Equatable, Sendable {
    public let powernap: Bool
    public let tcpkeepalive: Bool
    public let womp: Bool

    public init(powernap: Bool, tcpkeepalive: Bool, womp: Bool) {
        self.powernap = powernap
        self.tcpkeepalive = tcpkeepalive
        self.womp = womp
    }

    /// `womp` alone doesn't count against "off": Apple's battery default is `womp 0`.
    public var realSleep: RealSleepState {
        if !powernap && !tcpkeepalive && !womp { return .on }
        if powernap && tcpkeepalive { return .off }
        return .partial
    }
}

public enum RealSleepState: Equatable, Sendable {
    case on, off, partial
}

extension PowerSettings {
    /// Reads `powernap`, `tcpkeepalive` and `womp` per power source. A source missing any of them is left out.
    public static func networkWake(fromPmsetCustomOutput output: String) -> [PowerSource: NetworkWakeSettings] {
        var values: [PowerSource: [Substring: Bool]] = [:]
        var source: PowerSource?
        for line in output.split(separator: "\n") {
            if let first = line.first, !first.isWhitespace {
                source = line.hasSuffix(":") ? PowerSource(rawValue: String(line.dropLast())) : nil
                continue
            }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let source, fields.count == 2, ["powernap", "tcpkeepalive", "womp"].contains(fields[0]) else { continue }
            values[source, default: [:]][fields[0]] = fields[1] == "1"
        }
        return values.compactMapValues { v in
            guard let powernap = v["powernap"], let tcpkeepalive = v["tcpkeepalive"], let womp = v["womp"] else { return nil }
            return NetworkWakeSettings(powernap: powernap, tcpkeepalive: tcpkeepalive, womp: womp)
        }
    }
}
