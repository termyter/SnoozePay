import os
import XCTest
import UserNotifications
@testable import SnoozePay

/// Unit tests for AlarmScheduler — sound-file resolution, the permission
/// request, and the cancel sweep.
///
/// The notification-content cases that used to live here are gone with #472:
/// they pinned the title / subtitle / sound / interruption level of a
/// `UNMutableNotificationContent` the app no longer builds, because AlarmKit
/// renders the alert itself. The equivalent AlarmKit mapping (schedule,
/// presentation, sound) is pinned by `AlarmKitSchedulerTests`.
final class AlarmSchedulerTests: XCTestCase {

    private let scheduler = AlarmScheduler.shared

    // MARK: - Sound file resolution

    /// Both lookups in `alarmSoundFileName(for:)` are searches over
    /// ``AlarmScheduler/alarmSoundExtensions``, not `.caf` special cases.
    /// No other case in this file exercises an extension past `caf`, so
    /// collapsing either loop to a single `caf` probe would leave them green
    /// while a sound shipped as `.m4a` downgraded to `default_alarm` — the
    /// state #749 exists to report.
    ///
    /// Unconditional, two assertions per extension — one per lookup — on purpose. The version
    /// this replaces (`testAlarmSoundFileName_checksMultipleExtensions`)
    /// asserted `validExtensions.contains(ext)` under `if let`, so `nil` —
    /// the single answer that means the search found nothing — passed having
    /// run no assertion at all.
    ///
    /// The sink around the fallback half is there to keep the run QUIET, not
    /// to be read: that half takes the branch emitting
    /// `ALARM-749-SOUND-MISSING`, and a healthy suite must not write that ID
    /// into unified logging — it is the signal a support grep counts
    /// degraded installs by (#764). What the line SAYS is pinned by
    /// `testAlarmSoundFileName_missingSoundWithFallbackPresent_logsTheDowngrade`.
    func testAlarmSoundFileName_searchesEverySupportedExtensionInBothLookups() {
        for ext in AlarmScheduler.alarmSoundExtensions {
            XCTAssertEqual(
                scheduler.alarmSoundFileName(for: "radar") { name, candidate in
                    name == "radar" && candidate == ext
                },
                "radar.\(ext)",
                "a sound bundled only as .\(ext) must resolve, not downgrade to the fallback"
            )

            let viaFallback = AppLogger.withTestSink({ _, _, _ in }, perform: {
                scheduler.alarmSoundFileName(for: "vanished_sound") { name, candidate in
                    name == AlarmScheduler.fallbackSoundID && candidate == ext
                }
            })
            XCTAssertEqual(
                viaFallback,
                "\(AlarmScheduler.fallbackSoundID).\(ext)",
                "the fallback is searched under every extension too — a build carrying only "
                + "\(AlarmScheduler.fallbackSoundID).\(ext) still rings"
            )
        }
    }

    /// Runs through the DEFAULT lookup — no injected `resourceExists` — so it
    /// asserts the production path all the way into `Bundle.main`.
    ///
    /// Unconditional on purpose. The previous version wrapped both assertions
    /// in `if let name = result`, which made "the bundle has no sounds at all"
    /// a pass; that is the one outcome a shipped build must never have, and it
    /// is what `ALARM-749-DEFAULT-SOUND-MISSING` was added to report. The test
    /// host IS the app bundle (`TEST_HOST`), and `default_alarm.caf` sits flat
    /// at its root, so this also pins the injected-closure tests below to
    /// something real: empty the default closure and this case goes red while
    /// they stay green.
    func testAlarmSoundFileName_resolvesTheBundledDefaultThroughTheRealBundle() {
        XCTAssertEqual(
            scheduler.alarmSoundFileName(for: AlarmScheduler.fallbackSoundID),
            "default_alarm.caf",
            "the app bundle must carry its own fallback alarm sound — without it every "
            + "alarm rings AlarmKit's system tone"
        )
    }

    // MARK: - The two failing lookups leave distinguishable traces (#749)
    //
    // Returning nil is the contract with AlarmKit and is unchanged; what these
    // pin is that the branch says so. Until #749 a user report of "the alarm
    // rang with the wrong sound" had nothing to grep: a missing sound file, a
    // build with no default sound, and a perfectly resolved lookup were all
    // equally silent.

    func testAlarmSoundFileName_missingSoundWithFallbackPresent_logsTheDowngrade() {
        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        let result = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            scheduler.alarmSoundFileName(for: "vanished_sound") { name, ext in
                name == AlarmScheduler.fallbackSoundID && ext == "caf"
            }
        })

        XCTAssertEqual(result, "default_alarm.caf", "the fallback still answers — the alarm rings")

        let traces = lines.filter { $0.message.contains(AlarmScheduler.missingSoundErrorID) }
        XCTAssertEqual(
            traces.count, 1,
            "a sound the bundle lost must leave exactly one trace; the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(traces.first?.category, .audio, "a sound-resolution fault belongs to the Audio category")
        XCTAssertEqual(
            traces.first?.level, .error,
            "ringing something other than what the user chose is not a notice"
        )
        XCTAssertTrue(
            traces.first?.message.contains("vanished_sound") == true,
            "the line must name the soundID that was not found; it reads «\(traces.first?.message ?? "")»"
        )
    }

    /// The branch the real bundle cannot reach — the app ships
    /// `default_alarm.caf`, so only an injected lookup can state its absence.
    /// `.fault`, not `.error`: this one is a defective build, not a degraded
    /// install of a correct one.
    func testAlarmSoundFileName_nothingInTheBundle_logsTheBuildDefectAndStillReturnsNil() {
        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        let result = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            scheduler.alarmSoundFileName(for: "vanished_sound") { _, _ in false }
        })

        XCTAssertNil(result, "nil is the contract with AlarmKit and #749 must not change it")

        let traces = lines.filter { $0.message.contains(AlarmScheduler.missingFallbackSoundErrorID) }
        XCTAssertEqual(
            traces.count, 1,
            "a bundle without its default sound must leave exactly one trace; "
            + "the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(traces.first?.category, .audio, "a sound-resolution fault belongs to the Audio category")
        XCTAssertEqual(traces.first?.level, .fault, "a build shipped without its own alarm sound is a fault")
        XCTAssertTrue(
            traces.first?.message.contains("vanished_sound") == true,
            "the line must name the soundID that was not found; it reads «\(traces.first?.message ?? "")»"
        )
        XCTAssertTrue(
            lines.allSatisfy { !$0.message.contains(AlarmScheduler.missingSoundErrorID) },
            "the downgrade ID belongs to the branch where the alarm still rings; emitting both "
            + "here would make a support grep count one incident twice"
        )
    }

    /// Silence is load-bearing on the path that works: this runs on every
    /// scheduled alarm and every snooze re-fire, so a line here would put an
    /// `.error` in the log of a device where nothing is wrong.
    func testAlarmSoundFileName_soundPresent_logsNothing() {
        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        let result = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            scheduler.alarmSoundFileName(for: "radar") { name, ext in name == "radar" && ext == "caf" }
        })

        XCTAssertEqual(result, "radar.caf")
        XCTAssertTrue(lines.isEmpty, "a resolved lookup must stay silent; the sink saw \(lines.map(\.message))")
    }

    /// The IDs are what a support ticket is grepped by, so telling the two
    /// states apart depends on them staying different strings.
    func testAlarmSoundErrorIDs_areDistinct() {
        XCTAssertNotEqual(
            AlarmScheduler.missingSoundErrorID,
            AlarmScheduler.missingFallbackSoundErrorID,
            "a lost user sound and a build without a default sound must not grep as one thing"
        )
    }

    // MARK: - Permission
    //
    // Uses the injectable-backend seam. The old version called the REAL
    // UNUserNotificationCenter through `AlarmScheduler.shared` — on CI
    // simulators the permission daemon never answers, the completion never
    // fires and the test died on its 5s timeout.

    /// The reported grant is the ALARM grant. Before #472 this completion
    /// carried the NOTIFICATION grant, so a user who allowed notifications and
    /// refused alarms was told "granted" and got a permissions screen with a
    /// green card over an app that could not ring (#472).
    func testRequestPermission_reportsTheAlarmGrantNotTheNotificationOne() {
        let denied = AlarmScheduler(
            notificationCenter: PermissionStubCenter(grant: true),
            alarmKit: TestAlarmKitBackend(authorization: .denied)
        )
        let deniedExp = expectation(description: "denied completes")
        denied.requestPermission { granted in
            XCTAssertFalse(granted, "A granted notification must NOT read as a working alarm")
            deniedExp.fulfill()
        }
        wait(for: [deniedExp], timeout: 2.0)

        let authorized = AlarmScheduler(
            notificationCenter: PermissionStubCenter(grant: false),
            alarmKit: TestAlarmKitBackend()
        )
        let grantedExp = expectation(description: "granted completes")
        authorized.requestPermission { granted in
            XCTAssertTrue(granted, "An authorized AlarmKit backend is the whole answer")
            grantedExp.fulfill()
        }
        wait(for: [grantedExp], timeout: 2.0)
    }

    /// The notification permission is no longer requested at all: asking for a
    /// grant that can't ring anything trains the user to dismiss the one prompt
    /// that matters.
    func testRequestPermission_doesNotAskForNotifications() {
        let center = PermissionStubCenter(grant: true)
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: TestAlarmKitBackend())

        let exp = expectation(description: "requestPermission completes")
        scheduler.requestPermission { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(center.authorizationRequests, 0,
                       "No notification authorization request may be made (#472)")
    }

    func testRequestPermission_noBackend_completesWithoutCrash() {
        let scheduler = AlarmScheduler(notificationCenter: PermissionStubCenter(grant: false))
        let expectation = expectation(description: "requestPermission completes")
        scheduler.requestPermission { granted in
            XCTAssertFalse(granted, "No backend — completion must carry the denial through")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Cancel covers all trigger variants (regression for IOS-070)
    //
    // We add raw pending requests directly to UNUserNotificationCenter using the same
    // identifier scheme AlarmScheduler.schedule() uses, then call cancel(_:) and verify
    // that *every* variant — including the one-off "once" label that previously leaked —
    // is removed. We can't go through schedule() in the test process because that
    // requires notification permission and a real future trigger date.

    func testCancel_removesAllVariantsIncludingOnce() throws {
        let alarmID = UUID()
        let center = UNUserNotificationCenter.current()
        let prefix = "alarm_\(alarmID.uuidString)_"
        let snoozePrefix = "snooze_\(alarmID.uuidString)"

        // Identifiers that schedule() can produce: every weekday + once + snooze.
        let labels = ["day0", "day1", "day2", "day3", "day4", "day5", "day6", "once"]
        let scheduledIDs = labels.map { "\(prefix)\($0)" } + [snoozePrefix]

        // Use a far-future trigger so requests are accepted as pending.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60 * 24, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "test"

        let added = expectation(description: "all requests added")
        added.expectedFulfillmentCount = scheduledIDs.count
        for id in scheduledIDs {
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request) { _ in added.fulfill() }
        }
        wait(for: [added], timeout: 5.0)

        // Sanity: confirm at least one of our IDs landed in pending before we cancel.
        let beforeCancel = expectation(description: "pending fetched before cancel")
        var beforeIDs: Set<String> = []
        center.getPendingNotificationRequests { requests in
            beforeIDs = Set(requests.map { $0.identifier })
            beforeCancel.fulfill()
        }
        wait(for: [beforeCancel], timeout: 5.0)

        // The one skip in this target that is kept on purpose (#568).
        //
        // Every other `XCTSkipUnless` in `SnoozePayTests/` was a harness guard that
        // fired on every run and hid a case that had simply never been written to
        // run; those are now `XCTFail`. This one is different in kind: it is not a
        // claim about our own harness, it is a measured precondition about a system
        // service. `UNUserNotificationCenter` drops `add(_:)` on the floor when the
        // process has no notification authorization, and a CI test host has none —
        // nobody can tap "Allow", and the scheme cannot pre-grant it.
        //
        // Be clear about the cost: this case does skip on CI, on every run, so the
        // IOS-070 cancel-all-variants regression is currently pinned only by the
        // unit-level tests above it. It executes when the suite is run against a
        // simulator whose notification permission has been granted for this bundle
        // id (`xcrun simctl privacy <udid> grant notifications <bundle>`), which is
        // exactly what a would-be fix looks like: a CI step, i.e. a workflow change,
        // which is PM's call — or a notification-center seam on `AlarmScheduler`,
        // which is a production refactor rather than a test fix. Until one of those
        // happens, skipping is the honest report: the precondition is genuinely
        // absent, so asserting would measure UN's pre-permission behaviour, not
        // `cancel(_:)`.
        let landedIDs = beforeIDs.intersection(scheduledIDs)
        try XCTSkipIf(landedIDs.isEmpty,
                      "UNUserNotificationCenter did not accept test requests in this environment")

        // Act
        scheduler.cancel(alarmID)

        // Assert: poll up to 5s — cancel() goes through getPendingNotificationRequests
        // which is async, so we need to give it time to complete.
        let cancelled = expectation(description: "all variants cancelled")
        var remainingIDs: Set<String> = []
        let deadline = Date().addingTimeInterval(5.0)

        func poll() {
            center.getPendingNotificationRequests { requests in
                remainingIDs = Set(requests.map { $0.identifier }).intersection(scheduledIDs)
                if remainingIDs.isEmpty || Date() >= deadline {
                    cancelled.fulfill()
                } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { poll() }
                }
            }
        }
        poll()
        wait(for: [cancelled], timeout: 6.0)

        XCTAssertTrue(remainingIDs.isEmpty,
                      "cancel(_:) must remove every notification for the alarm — leaked: \(remainingIDs)")
    }
}

// MARK: - Test double

/// Minimal `NotificationScheduling` stub for the permission-path tests:
/// answers `requestAuthorization` synchronously with the configured grant
/// and treats every other member as a no-op. Keeps the permission tests
/// deterministic on simulators where the real daemon never answers (CI).
private final class PermissionStubCenter: NotificationScheduling {
    private let grant: Bool
    /// How many times the app asked the OS for notification authorization.
    /// Must stay 0 since #472.
    private(set) var authorizationRequests = 0

    init(grant: Bool) { self.grant = grant }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        authorizationRequests += 1
        completionHandler(grant, nil)
    }

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: ((Error?) -> Void)?
    ) {
        completion?(nil)
    }
    func getPendingNotificationRequests(
        completionHandler: @escaping ([UNNotificationRequest]) -> Void
    ) {
        completionHandler([])
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func getDeliveredNotifications(
        completionHandler: @escaping ([UNNotification]) -> Void
    ) {
        completionHandler([])
    }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func removeAllPendingNotificationRequests() {}
}
