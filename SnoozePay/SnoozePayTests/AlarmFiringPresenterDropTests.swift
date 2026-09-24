import os
import XCTest
@testable import SnoozePay

/// The branch where `AlarmFiringPresenter` finds no host: nothing in the scene
/// can host the firing screen, so no screen goes up and the alarm is parked for
/// the next flush. The audio is left alone since #875, as after a swap: the
/// alarm's screen is still coming (`AlarmFiringPresenterMissRuleTests`). It
/// used to stop there, without parking anything; since #834 it arms the retry
/// itself (pinned in
/// `AlarmFiringPresenterSwapGuardTests`, section "The notification path").
///
/// It is the loudest outcome this class has — the user is left with nothing to
/// look at until the retry lands — and until #795 its only
/// evidence was one `os.Logger` line that no test in the target read
/// (`grep -rn "firing-present" SnoozePayTests/` found nothing). A line only
/// unified logging can see is a line nobody can assert on, so deleting it or
/// the `return false` the pending-present retry (#382) keys off would both
/// have left the suite green.
///
/// Reached through the ``AlarmFiringPresenter/locateHost`` seam, because the
/// real walk reads `UIApplication.shared.connectedScenes` and a unit test owns
/// exactly one scene, permanently populated — the same reason
/// ``AlarmFiringPresenter/isRootReady`` is a seam (#382). Which states the
/// locator answers a ``ActiveWindowLocator/Miss`` for is `ActiveWindowLocator`'s
/// own question and is covered in `ActiveWindowLocatorTests`.
@MainActor
final class AlarmFiringPresenterDropTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        super.tearDown()
    }

    /// The whole outcome in one test: the line names the reason, the alarm
    /// keeps ringing, and the caller is told to retry.
    func testPresent_whenNothingCanHostTheScreen_namesTheMissKeepsTheSoundAndAsksForARetry() {
        let presenter = AlarmFiringPresenter(alarmRepository: .shared)
        presenter.locateHost = { .failure(.noHostingWindow) }

        // Real audio, not a stand-in: "still ringing" asserted from a silent
        // start would pass with a stop added back. A missing bundle sound
        // falls back to the synthetic tone, which is how `AudioServiceTests` gets a playing
        // service without a device.
        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(
            AudioService.shared.isPlaying,
            "test precondition: the alarm has to be audible, or «still ringing» proves nothing"
        )

        var lines: [Line] = []
        var mounted = true
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            mounted = presenter.present(alarm: Alarm())
        })

        XCTAssertFalse(
            mounted,
            """
            «no window to present in» is the one signal the pending-present \
            retry (#382) keys off; answering true drops the firing screen for \
            good instead of re-attempting on scene-active
            """
        )
        XCTAssertTrue(
            AudioService.shared.isPlaying,
            """
            the miss keeps the alarm pending, so its sound is left alone (#875): \
            silenced here, it waits for an activation the foreground app never gets
            """
        )

        guard let line = lines.first(where: { $0.message.contains("firing-present") }) else {
            return XCTFail(
                """
                the drop left no line the suite can read. This branch has no \
                other evidence — no screen appears, and nothing else says why. \
                The sink saw \
                \(lines.map(\.message))
                """
            )
        }
        XCTAssertTrue(
            line.message.contains(ActiveWindowLocator.Miss.noHostingWindow.rawValue),
            """
            the line has to carry the locator's reason — the three misses are \
            fixed differently, and one shared sentence puts them back into one \
            grep. It reads «\(line.message)»
            """
        )
        XCTAssertEqual(
            line.level, .error,
            "an alarm with no screen is a failure, not the expected background-delivery notice"
        )
        XCTAssertEqual(
            line.category, .appDelegate,
            "the line has to land in the category a support grep for the firing path filters by"
        )
    }

    /// And the reason is read off the miss rather than spelled once: a drop for
    /// a different state has to say that state.
    ///
    /// Without this, `"firing-present: no normal-level window …"` written out as
    /// a constant would satisfy the test above while reporting a cold launch —
    /// no scene attached at all — as a scene whose windows cannot host, which
    /// is the fold #795 took apart.
    func testPresent_whenTheProcessHasNoSceneYet_saysThatRatherThanBlamingTheWindows() {
        let presenter = AlarmFiringPresenter(alarmRepository: .shared)
        presenter.locateHost = { .failure(.noScene) }

        var lines: [Line] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            _ = presenter.present(alarm: Alarm())
        })

        guard let line = lines.first(where: { $0.message.contains("firing-present") }) else {
            return XCTFail("the drop left no line at all; the sink saw \(lines.map(\.message))")
        }
        XCTAssertTrue(
            line.message.contains(ActiveWindowLocator.Miss.noScene.rawValue),
            """
            a cold launch reported as «no window has a root» sends the reader \
            hunting rootless windows in a process that has no windows yet. It \
            reads «\(line.message)»
            """
        )
    }
}
