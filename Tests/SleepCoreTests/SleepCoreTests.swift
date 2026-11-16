import Foundation
import Testing
@testable import SleepCore

// Real output captured on 2026-10-30, trimmed.
private let assertionsSample = """
2026-10-30 15:33:21 +0200 
Assertion status system-wide:
   UserIsActive                   1
   PreventUserIdleDisplaySleep    1
   PreventUserIdleSystemSleep     1
Listed by owning process:
   pid 9454(caffeinate): [0x000ad9f700059b0c] 29:28:06 PreventUserIdleDisplaySleep named: "caffeinate command-line tool"  
	Details: caffeinate asserting forever
	Localized=THE CAFFEINATE TOOL IS PREVENTING SLEEP.
   pid 594(WindowServer): [0x000c040200098611] 00:00:04 UserIsActive named: "com.apple.iohideventsystem.queue.tickle"  
	Timeout will fire in 1195 secs Action=TimeoutActionRelease
   pid 533(powerd): [0x000bbd600001a17a] 05:32:17 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"  
   pid 15765(Claude): [0x000bd921000180f8] 03:33:52 NoIdleSleepAssertion named: "Electron"  
Kernel Assertions: 0x104=USB,MAGICWAKE
   id=558  level=255 0x100=MAGICWAKE creat=07/10/2026, 12:45  mod=30/10/2026, 15:02 description=en0 owner=IOSkywalkNetworkBSDClient
"""

@Test func parsesProcessAssertions() {
    let assertions = Assertions.parse(assertionsSample)
    #expect(assertions.map(\.process) == ["caffeinate", "WindowServer", "powerd", "Claude"])
    #expect(assertions[0] == Assertion(pid: 9454, process: "caffeinate", type: "PreventUserIdleDisplaySleep",
                                       name: "caffeinate command-line tool", seconds: 29 * 3600 + 28 * 60 + 6))
    #expect(assertions[0].prevents == "Display sleep")
    #expect(assertions[2].prevents == "System sleep while display is on")
    #expect(assertions[3].prevents == "Idle system sleep")
    #expect(assertions.filter { !$0.isNoise }.count == 3)
}

@Test func parsesEmptyOutput() {
    #expect(Assertions.parse("Assertion status system-wide:\nListed by owning process:\n").isEmpty)
}

@Test func formatsDurations() {
    #expect(Assertions.formatDuration(seconds: 4) == "a few seconds")
    #expect(Assertions.formatDuration(seconds: 3 * 3600 + 33 * 60 + 52) == "3 h 33 min")
    #expect(Assertions.formatDuration(seconds: 2 * 3600) == "2 h")
    #expect(Assertions.formatDuration(seconds: 125) == "2 min")
}

@Test func readsSleepDisabled() {
    #expect(PowerSettings.sleepDisabled(fromPmsetOutput: "System-wide power settings:\n SleepDisabled\t\t1\n") == true)
    #expect(PowerSettings.sleepDisabled(fromPmsetOutput: " SleepDisabled\t\t0\nCurrently in use:\n") == false)
    #expect(PowerSettings.sleepDisabled(fromPmsetOutput: "Currently in use:\n sleep 1\n") == nil)
}

// `pmset -g custom` captured on 2026-11-07, trimmed.
private let customSample = """
Battery Power:
 Sleep On Power Button 1
 powernap             1
 womp                 0
 sleep                1
 tcpkeepalive         1
AC Power:
 Sleep On Power Button 1
 powernap             1
 womp                 1
 tcpkeepalive         1
 disksleep            10
"""

@Test func readsBatteryAndACSettings() {
    let settings = PowerSettings.networkWake(fromPmsetCustomOutput: customSample)
    #expect(settings[.battery] == NetworkWakeSettings(powernap: true, tcpkeepalive: true, womp: false))
    #expect(settings[.ac] == NetworkWakeSettings(powernap: true, tcpkeepalive: true, womp: true))
    #expect(settings[.battery]?.realSleep == .off)
}

@Test func realSleepOnWhenAllOff() {
    #expect(NetworkWakeSettings(powernap: false, tcpkeepalive: false, womp: false).realSleep == .on)
}

@Test func partialWhenSettingsDisagree() {
    #expect(NetworkWakeSettings(powernap: false, tcpkeepalive: true, womp: false).realSleep == .partial)
    #expect(NetworkWakeSettings(powernap: false, tcpkeepalive: false, womp: true).realSleep == .partial)
}

@Test func noBatterySection() {
    let settings = PowerSettings.networkWake(fromPmsetCustomOutput: "AC Power:\n powernap 1\n womp 1\n tcpkeepalive 1\n")
    #expect(settings[.battery] == nil)
    #expect(settings[.ac] != nil)
}

// sudoers only allows the exact argument lists in the rule, so the app's must match setup.sh word for word.
@Test func realSleepCommandsMatchSudoersRule() throws {
    let setup = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../scripts/setup.sh")
    let rule = try #require(try String(contentsOf: setup, encoding: .utf8)
        .split(separator: "\n").first { $0.contains("NOPASSWD:") })
    for arguments in [SleepControl.realSleepOnArguments, SleepControl.realSleepOffArguments] {
        #expect(rule.contains(([SleepControl.pmset] + arguments).joined(separator: " ")))
    }
}
