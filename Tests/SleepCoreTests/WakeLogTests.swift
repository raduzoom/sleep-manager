import Foundation
import Testing
@testable import SleepCore

// Real `pmset -g log` lines from 2026-11-03 to 2026-11-07, trimmed. The log separates the event type from the
// message with a tab.
private let logSample = """
2026-11-03 13:41:02 +0200 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty/HID Activity Using BATT (Charge:69%)
2026-11-03 19:52:59 +0200 Sleep               \tEntering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:49%) 35 secs
2026-11-06 21:12:56 +0200 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to NUB.SPMISw3IRQ nub-spmi0.0x02 rtc/Maintenance Using BATT (Charge:1%) 6 secs
2026-11-06 22:11:47 +0200 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:1%) 29 secs
2026-11-06 22:12:16 +0200 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:1%) 16 secs
2026-11-06 22:12:32 +0200 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:1%) 27 secs
2026-11-06 22:12:59 +0200 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:1%) 19 secs
2026-11-06 22:13:18 +0200 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:1%) 35 secs
2026-11-06 22:13:53 +0200 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:1%) 7 secs
2026-11-06 22:14:00 +0200 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:1%) 29 secs
2026-11-06 22:14:29 +0200 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:1%) 8 secs
2026-11-06 22:14:37 +0200 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:1%) 14 secs
2026-11-06 22:14:51 +0200 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:1%) 3 secs
2026-11-06 22:14:54 +0200 Sleep               \tEntering Sleep state due to 'Low Power Sleep':TCPKeepAlive=inactive Using Batt (Charge:1%) 48386 secs
2026-11-06 22:14:56 +0200 Wake Requests       \t[process=mDNSResponder request=Maintenance deltaSecs=6477 wakeAt=2026-11-07 00:02:53 info="DHCP lease renewal"]
2026-11-07 11:41:20 +0200 Wake                \tWake from Hibernate [CDNVA] : due to acattach/UserActivity Assertion Using AC (Charge:4%)
"""

private func date(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    return formatter.date(from: text)!
}

@Test func reasonFromWifiWake() {
    let message = "DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:1%) 16 secs"
    #expect(WakeLog.reason(fromDarkWakeMessage: message) == "wifibt")
}

@Test func reasonFromTimedWake() {
    let message = "DarkWake from Deep Idle [CDNP] : due to NUB.SPMISw3IRQ nub-spmi0.0x02 rtc/Maintenance Using BATT (Charge:1%) 6 secs"
    #expect(WakeLog.reason(fromDarkWakeMessage: message) == "rtc")
}

@Test func countsDarkWakesInLastSleep() throws {
    let summary = try #require(WakeLog.lastSleep(fromPmsetLog: logSample))
    #expect(summary.darkWakes == 6)
    #expect(summary.mainReason == "wifibt")
    #expect(summary.chargeAtStart == 49)
    #expect(summary.chargeAtEnd == 1)
    #expect(summary.start == date("2026-11-03 19:52:59 +0200"))
    #expect(summary.end == date("2026-11-07 11:41:20 +0200"))
}

@Test func nilWithoutFullWake() {
    let onlySleeping = logSample.split(separator: "\n").filter { !$0.contains(" Wake      ") }.joined(separator: "\n")
    #expect(WakeLog.lastSleep(fromPmsetLog: onlySleeping) == nil)
    #expect(WakeLog.lastSleep(fromPmsetLog: "") == nil)
}

@Test func describesSummary() {
    let start = date("2026-11-03 19:52:59 +0200"), end = date("2026-11-07 11:41:20 +0200")
    func summary(_ wakes: Int, _ charge: Int?) -> SleepSummary {
        SleepSummary(start: start, end: end, darkWakes: wakes, mainReason: wakes > 0 ? "wifibt" : nil,
                     chargeAtStart: charge, chargeAtEnd: 1)
    }
    #expect(WakeLog.describe(summary(1705, 38)) == "Last sleep (87 h 48 min): woke 1,705 times (wifibt) · 38% → 1%")
    #expect(WakeLog.describe(summary(1, nil)) == "Last sleep (87 h 48 min): woke once (wifibt)")
    #expect(WakeLog.describe(summary(0, 38)) == "Last sleep (87 h 48 min): didn't wake · 38% → 1%")
}

// Real `pmset -g log` has indented detail lines with a tab near the start.
@Test func skipsIndentedDetailLines() {
    let log = logSample + "\n\tTimeout will fire in 595 secs Action=TimeoutActionRelease\nshort\tline"
    #expect(WakeLog.lastSleep(fromPmsetLog: log)?.darkWakes == 6)
}
