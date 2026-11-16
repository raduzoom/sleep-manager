import Foundation

/// The most recent stretch between going to sleep and the next full wake, from `pmset -g log`.
public struct SleepSummary: Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// Brief wakes while asleep, during which apps get a few seconds to run.
    public let darkWakes: Int
    /// The most common wake source, e.g. `wifibt` (Wi-Fi/Bluetooth) or `rtc` (a timer).
    public let mainReason: String?
    public let chargeAtStart: Int?
    public let chargeAtEnd: Int?

    public init(start: Date, end: Date, darkWakes: Int, mainReason: String?, chargeAtStart: Int?, chargeAtEnd: Int?) {
        self.start = start
        self.end = end
        self.darkWakes = darkWakes
        self.mainReason = mainReason
        self.chargeAtStart = chargeAtStart
        self.chargeAtEnd = chargeAtEnd
    }
}

public enum WakeLog {
    /// Nil when the log has no full wake after a sleep.
    public static func lastSleep(fromPmsetLog log: String) -> SleepSummary? {
        var last: SleepSummary?
        // The sleep in progress: nil while the Mac is awake.
        var start: Date?
        var chargeAtStart: Int?
        var chargeAtEnd: Int?
        var darkWakes = 0
        var reasons: [(reason: String, count: Int)] = []

        for line in log.split(separator: "\n") {
            // "2026-11-06 22:12:16 +0200 DarkWake            \tDarkWake from ..."
            // Indented detail lines ("\tTimeout will fire in ...") have their tab before the type column.
            guard line.first?.isNumber == true, line.count > 26, let tab = line.firstIndex(of: "\t") else { continue }
            let typeStart = line.index(line.startIndex, offsetBy: 26)
            guard typeStart <= tab else { continue }
            let type = line[typeStart..<tab].trimmingCharacters(in: .whitespaces)
            let message = line[line.index(after: tab)...]
            switch type {
            case "Sleep" where start == nil:
                guard let date = date(line.prefix(25)) else { continue }
                start = date
                chargeAtStart = charge(in: message)
                chargeAtEnd = chargeAtStart
                darkWakes = 0
                reasons = []
            case "Sleep":
                chargeAtEnd = charge(in: message) ?? chargeAtEnd
            case "DarkWake" where start != nil:
                darkWakes += 1
                chargeAtEnd = charge(in: message) ?? chargeAtEnd
                if let reason = reason(fromDarkWakeMessage: String(message)) {
                    if let i = reasons.firstIndex(where: { $0.reason == reason }) {
                        reasons[i].count += 1
                    } else {
                        reasons.append((reason, 1))
                    }
                }
            case "Wake":
                guard let sleepStart = start, let end = date(line.prefix(25)) else { continue }
                // max(by:) keeps the last of equal counts, so reverse to prefer the reason seen first.
                let main = reasons.reversed().max { $0.count < $1.count }?.reason
                last = SleepSummary(start: sleepStart, end: end, darkWakes: darkWakes, mainReason: main,
                                    chargeAtStart: chargeAtStart, chargeAtEnd: chargeAtEnd)
                start = nil
            default:
                continue
            }
        }
        return last
    }

    /// The first plain word after "due to": "smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/" gives "wifibt".
    public static func reason(fromDarkWakeMessage message: String) -> String? {
        guard let due = message.range(of: "due to ") else { return nil }
        var cause = message[due.upperBound...]
        if let using = cause.range(of: " Using") { cause = cause[..<using.lowerBound] }
        return cause.split(whereSeparator: { $0 == " " || $0 == "/" })
            .first { !$0.contains(".") && !$0.contains("(") }
            .map(String.init)
    }

    /// The grey menu line, e.g. "Last sleep (9 h 12 min): woke 1,705 times (wifibt) · 38% → 1%". The length tells a
    /// short nap apart from the night it replaced.
    public static func describe(_ summary: SleepSummary) -> String {
        let length = Assertions.formatDuration(seconds: Int(summary.end.timeIntervalSince(summary.start)))
        var text = "Last sleep (\(length)): "
        switch summary.darkWakes {
        case 0: text += "didn't wake"
        case 1: text += "woke once"
        default:
            let count = summary.darkWakes.formatted(.number.locale(Locale(identifier: "en_US")))
            text += "woke \(count) times"
        }
        if summary.darkWakes > 0, let reason = summary.mainReason { text += " (\(reason))" }
        if let from = summary.chargeAtStart, let to = summary.chargeAtEnd { text += " · \(from)% → \(to)%" }
        return text
    }

    private static func charge(in message: Substring) -> Int? {
        guard let range = message.range(of: "Charge:") else { return nil }
        return Int(message[range.upperBound...].prefix(while: \.isNumber))
    }

    private static func date(_ text: Substring) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: String(text))
    }
}
