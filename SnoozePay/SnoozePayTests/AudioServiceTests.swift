import AVFoundation
import os
import XCTest
@testable import SnoozePay

/// Unit tests for AudioService — alarm sound playback state management.
final class AudioServiceTests: XCTestCase {

    // MARK: - Synthetic tone (#210)

    /// The in-memory WAV fallback must produce a ready AVAudioPlayer — if it
    /// ever returns nil the alarm fires vibration-only, which previously
    /// happened without a trace (`try?`). Now the failure path logs, and this
    /// test pins the happy path so the generated WAV header stays valid.
    func testGenerateAlarmTone_returnsPlayer() {
        XCTAssertNotNil(AudioService.generateAlarmTone(),
                        "Synthetic tone generation must succeed for valid in-memory WAV data")
    }

    // MARK: - Start

    func testStartAlarmSound_setsIsPlaying() {
        let service = AudioService.shared
        // Ensure clean state
        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)

        service.startAlarmSound(soundID: "nonexistent_test_sound")
        // Missing bundle file → AudioService falls back to a synthetic tone
        // (generateAlarmTone). isPlaying must be true to reflect that real audio
        // is being produced, not just vibration.
        XCTAssertTrue(service.isPlaying)

        // Cleanup
        service.stopAlarmSound()
    }

    /// IOS-037 — silent failure regression guard.
    /// When the bundle does not contain the requested sound file, AudioService
    /// must fall back to the synthetic tone instead of silently going
    /// vibration-only with isPlaying = true.
    func testStartAlarmSound_withMissingFile_fallsBackToSynthetic() {
        let service = AudioService.shared
        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)

        service.startAlarmSound(soundID: "definitely_not_a_real_sound_file_xyz")
        // Synthetic tone generation is deterministic and does not depend on
        // audio session state for unit-test correctness — isPlaying reflects
        // the in-memory player being created and started.
        XCTAssertTrue(
            service.isPlaying,
            "Missing bundle file should fall back to synthetic tone, not silent vibration"
        )

        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)
    }

    // NOTE: We cannot easily simulate AVAudioSession.setActive failure without
    // a DI refactor (AVAudioSession is a hard-coded singleton inside AudioService).
    // A follow-up could introduce a session-providing protocol so the
    // setActive-throws path can be exercised in unit tests.

    func testStartAlarmSound_whenAlreadyPlaying_doesNotRestart() {
        let service = AudioService.shared
        service.stopAlarmSound()

        // Start the first time
        service.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(service.isPlaying)

        // Calling start again should be a no-op (guard !isPlaying)
        // The fact that it doesn't crash and isPlaying remains true confirms the guard
        service.startAlarmSound(soundID: "another_nonexistent_sound")
        XCTAssertTrue(service.isPlaying)

        // Cleanup
        service.stopAlarmSound()
    }

    // MARK: - Stop

    func testStopAlarmSound_stopsPlaying() {
        let service = AudioService.shared
        service.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(service.isPlaying)

        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)
    }

    func testStopAlarmSound_whenNotPlaying_doesNotCrash() {
        let service = AudioService.shared
        // Ensure we're in a stopped state
        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)

        // Calling stop again should not crash
        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)
    }

    // MARK: - Round-trip

    func testStartAndStopCycle_resetsState() {
        let service = AudioService.shared
        service.stopAlarmSound()

        service.startAlarmSound(soundID: "test")
        XCTAssertTrue(service.isPlaying)

        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)

        // Can restart after stopping
        service.startAlarmSound(soundID: "test")
        XCTAssertTrue(service.isPlaying)

        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)
    }

    // MARK: - State + notifications (IOS-077)

    /// Successful start path must transition state through `.stopped → .playing`
    /// and broadcast the change via `stateChangedNotification`.
    func testStartAlarmSound_postsPlayingStateNotification() {
        let service = AudioService.shared
        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)

        var observedStates: [AudioPlaybackState] = []
        let token = NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: service,
            queue: nil
        ) { note in
            if let state = note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState {
                observedStates.append(state)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        service.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertEqual(service.state, .playing)
        XCTAssertTrue(observedStates.contains(.playing),
                      "Expected .playing state to be broadcast, got \(observedStates)")

        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertTrue(observedStates.contains(.stopped),
                      "Expected .stopped state to be broadcast, got \(observedStates)")
    }

    // MARK: - Ownership tracking (IOS-116)

    /// `currentAlarmID` must reflect the alarm that started the current session
    /// and clear back to nil after `stopAlarmSound()`.
    func testCurrentAlarmID_setOnStart_clearedOnStop() {
        let service = AudioService.shared
        service.stopAlarmSound()
        XCTAssertNil(service.currentAlarmID)

        let alarmID = UUID()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarmID)
        XCTAssertEqual(service.currentAlarmID, alarmID)

        service.stopAlarmSound()
        XCTAssertNil(service.currentAlarmID)
    }

    /// IOS-116 — alarm-stacking race regression guard.
    ///
    /// Sequence:
    ///   1. Alarm A starts → owns the audio session.
    ///   2. AppDelegate dismisses A's firing VC and presents B's; B's
    ///      `viewDidLoad` calls `startAlarmSound(alarmID: B)` while A's
    ///      `viewDidDisappear` has not yet fired.
    ///   3. A's `viewDidDisappear` finally runs and would normally call
    ///      `stopAlarmSound()` — but with the new ownership check, it sees
    ///      `currentAlarmID != A.id` and skips the stop, preserving B's audio.
    ///
    /// We can't simulate the VC lifecycle in a unit test directly, so we
    /// reproduce the *contract* the VC relies on: after a second start with a
    /// different ID, the previous owner has lost the session.
    func testStartAlarmSound_secondStartOverridesOwnership() {
        let service = AudioService.shared
        service.stopAlarmSound()

        let alarmA = UUID()
        let alarmB = UUID()

        service.startAlarmSound(soundID: "tone_a", alarmID: alarmA)
        XCTAssertEqual(service.currentAlarmID, alarmA)

        // Simulating B taking over — startAlarmSound is guarded by `state == .stopped`,
        // so the second call short-circuits, but it still must transfer ownership
        // so the dismissed-VC's stop check skips correctly.
        service.startAlarmSound(soundID: "tone_b", alarmID: alarmB)
        XCTAssertEqual(
            service.currentAlarmID,
            alarmB,
            "Second startAlarmSound must transfer ownership to the new alarm so " +
            "the previous VC's viewDidDisappear does not silence it (#116)"
        )

        // Now A's "viewDidDisappear" check would compare `currentAlarmID == alarmA`,
        // see false, and refuse to stop — emulate that and confirm audio still plays.
        if service.currentAlarmID == alarmA {
            service.stopAlarmSound()
        }
        XCTAssertTrue(
            service.isPlaying,
            "Audio for alarm B must keep playing when A's VC dismisses after the handoff"
        )

        service.stopAlarmSound()
    }

    /// Restarting while already playing must not re-emit `.playing` (didSet
    /// guards on equality). This protects observers from spurious banner flicker.
    func testStateNotification_notRepostedOnSameState() {
        let service = AudioService.shared
        service.stopAlarmSound()

        var emissionCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: service,
            queue: nil
        ) { _ in emissionCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        service.startAlarmSound(soundID: "x") // → .playing  (1)
        let afterFirstStart = emissionCount

        // Second call hits `guard state == .stopped` and returns early — no new
        // notification should fire.
        service.startAlarmSound(soundID: "y")
        XCTAssertEqual(emissionCount, afterFirstStart,
                       "Re-entrant start must not republish the same state")

        service.stopAlarmSound()
    }

    // MARK: - Thread safety (#202)

    /// `startAlarmSound` may be called from a UN-delegate background thread
    /// (AppDelegate's `willPresent` is not guaranteed main). The serial-queue
    /// hop must make the call fully synchronous and leave the service in a
    /// consistent state observable from the main thread.
    func testStartAlarmSound_fromBackgroundThread_reachesPlayingState() {
        let service = AudioService.shared
        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)

        let alarmID = UUID()
        let started = expectation(description: "background start completed")
        DispatchQueue.global(qos: .userInitiated).async {
            service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarmID)
            started.fulfill()
        }
        wait(for: [started], timeout: 5)

        XCTAssertEqual(service.state, .playing,
                       "Background-thread start must land in .playing like a main-thread start")
        XCTAssertEqual(service.currentAlarmID, alarmID)

        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertNil(service.currentAlarmID)
    }

    /// TSan-style stress test: hammer start/stop/reads from many threads at
    /// once. Before the serial queue, `state` / `currentAlarmID` /
    /// `audioPlayer` / `vibrationTimer` were mutated without synchronization
    /// and could land in inconsistent combinations (e.g. `.playing` with a
    /// nil player). With the queue this must never crash and must end in a
    /// coherent state after the final stop.
    func testConcurrentStartStop_doesNotCorruptState() {
        let service = AudioService.shared
        service.stopAlarmSound()

        let iterations = 50
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            if index.isMultiple(of: 2) {
                service.startAlarmSound(soundID: "stress_sound", alarmID: UUID())
            } else {
                service.stopAlarmSound()
            }
            // Interleave reads — these raced with the writers before #202.
            _ = service.state
            _ = service.isPlaying
            _ = service.currentAlarmID
        }

        // Whatever interleaving happened, the snapshot must be one of the
        // legal states — and a final stop must always win.
        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertNil(service.currentAlarmID)
        XCTAssertFalse(service.isPlaying)

        // Service must remain usable after the stress run.
        service.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(service.isPlaying)
        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
    }

    /// Pause/resume (#141) mutate the same queue-confined fields — calling
    /// them from a background thread while the main thread reads must keep
    /// state coherent (`.playing` is intentionally retained across pause).
    func testPauseResume_fromBackgroundThread_keepsStateCoherent() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
        XCTAssertEqual(service.state, .playing)

        let cycled = expectation(description: "background pause/resume completed")
        DispatchQueue.global(qos: .userInitiated).async {
            service.pauseAlarmSound()
            service.resumeAlarmSound()
            cycled.fulfill()
        }
        wait(for: [cycled], timeout: 5)

        XCTAssertEqual(service.state, .playing,
                       "pause+resume must preserve .playing (session ownership intact)")

        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
    }

    // MARK: - Pause / interruption state (#374)

    /// Post a synthetic `AVAudioSession` interruption so the service's observer
    /// runs its handler. The handler hops the serial queue with `queue.sync`,
    /// and `NotificationCenter.post` delivers synchronously on this thread, so
    /// the service state is fully settled when `post` returns.
    private func postInterruption(_ type: AVAudioSession.InterruptionType) {
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue]
        )
    }

    /// `pauseAlarmSound()` must flip `isPaused` while keeping `.playing`
    /// (session ownership intact, #141); `resumeAlarmSound()` clears it.
    func testPauseResume_togglesIsPaused() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
        XCTAssertTrue(service.isPlaying)
        XCTAssertFalse(service.isPaused)

        service.pauseAlarmSound()
        XCTAssertTrue(service.isPaused, "pause must mark the session as not audible")
        XCTAssertEqual(service.state, .playing, "pause keeps .playing (session owned)")

        service.resumeAlarmSound()
        XCTAssertFalse(service.isPaused, "resume must clear the paused flag")
        XCTAssertEqual(service.state, .playing)

        service.stopAlarmSound()
        XCTAssertFalse(service.isPaused)
    }

    /// #374 facet 2 — a new alarm firing while the session is paused (top-up
    /// sheet open) must un-pause so it is immediately audible, not silent until
    /// the 60s auto-resume. Ownership still transfers to the new alarm (#116).
    func testStartWhilePaused_unPausesAndTransfersOwnership() {
        let service = AudioService.shared
        service.stopAlarmSound()

        let alarmA = UUID()
        let alarmB = UUID()
        service.startAlarmSound(soundID: "tone_a", alarmID: alarmA)
        service.pauseAlarmSound()
        XCTAssertTrue(service.isPaused)

        // Alarm B fires into the paused session.
        service.startAlarmSound(soundID: "tone_b", alarmID: alarmB)
        XCTAssertFalse(service.isPaused, "a new alarm must un-pause the session so it rings")
        XCTAssertEqual(service.currentAlarmID, alarmB, "ownership transfers to the new alarm (#116)")
        XCTAssertTrue(service.isPlaying)

        service.stopAlarmSound()
    }

    /// #374 facet 1 — an interruption (call/Siri) pauses the alarm; when it ends
    /// the alarm must resume (a permanently silent alarm is a failed wake).
    func testInterruption_pausesOnBeganAndResumesOnEnded() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
        XCTAssertFalse(service.isPaused)

        postInterruption(.began)
        XCTAssertTrue(service.isPaused, "interruption .began must pause the alarm")
        XCTAssertEqual(service.state, .playing, "session is still owned across the interruption")

        postInterruption(.ended)
        XCTAssertFalse(service.isPaused, "interruption .ended must auto-resume the alarm")
        XCTAssertEqual(service.state, .playing)

        service.stopAlarmSound()
    }

    /// An `.ended` with no preceding `.began` (we were never interrupted) must
    /// be a no-op rather than spuriously toggling state.
    func testInterruptionEnded_withoutBegan_isNoOp() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())

        postInterruption(.ended)
        XCTAssertFalse(service.isPaused)
        XCTAssertEqual(service.state, .playing)

        service.stopAlarmSound()
    }

    /// A system interruption that arrives while a top-up pause (#141) is already
    /// in effect must not hijack the pause: `.ended` must NOT auto-resume,
    /// leaving the manual `resumeAlarmSound()` in control.
    func testInterruption_duringTopUpPause_doesNotAutoResume() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
        service.pauseAlarmSound()          // top-up pause
        XCTAssertTrue(service.isPaused)

        postInterruption(.began)           // guarded out (already paused)
        postInterruption(.ended)           // must not auto-resume the top-up pause
        XCTAssertTrue(service.isPaused, "top-up pause must survive an interruption cycle")

        service.resumeAlarmSound()
        XCTAssertFalse(service.isPaused)

        service.stopAlarmSound()
    }

    // MARK: - Session reactivation on resume (#395)

    /// #395 facet 1 — every resume must reclaim the audio session before
    /// `play()`. iOS deactivates the session during an interruption; a
    /// `play()` against a dead session is silent with no error (a failed wake).
    /// `sessionActivationCount` increasing on resume proves the reactivation
    /// path actually ran.
    func testResumeAlarmSound_reactivatesSession() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
        let afterStart = service.sessionActivationCount

        service.pauseAlarmSound()
        service.resumeAlarmSound()
        XCTAssertEqual(
            service.sessionActivationCount, afterStart + 1,
            "resumeAlarmSound must reactivate the session (it may be dead after an interruption, #395)"
        )
        XCTAssertFalse(service.isPaused)
        XCTAssertEqual(service.state, .playing)

        service.stopAlarmSound()
    }

    /// #395 core scenario — a top-up pause (#141) overlaps an incoming call.
    /// The `.began` is guarded out because `_isPaused` is already set, so iOS
    /// silently tears the session down. When the top-up sheet dismisses,
    /// `resumeAlarmSound()` must reactivate the session — otherwise the alarm
    /// plays against a dead session and the user never wakes.
    func testTopUpPauseThenInterruption_resumeReactivatesSession() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())

        service.pauseAlarmSound()          // top-up sheet opens
        postInterruption(.began)           // call arrives, guarded out, session torn down
        XCTAssertTrue(service.isPaused, "top-up pause stays in effect through the interruption")

        let beforeResume = service.sessionActivationCount
        service.resumeAlarmSound()         // sheet dismisses
        XCTAssertEqual(
            service.sessionActivationCount, beforeResume + 1,
            "resume after a top-up-pause+interruption must reclaim the dead session (#395)"
        )
        XCTAssertFalse(service.isPaused)
        XCTAssertEqual(service.state, .playing)

        service.stopAlarmSound()
    }

    /// #395 facet 2 — `resumeAlarmSound()` must NOT clear `_interrupted`. If a
    /// real interruption is active and a top-up resume fires concurrently, the
    /// old code reset `_interrupted=false`, so the later `.ended` no-op'd and
    /// the alarm never auto-resumed. Here the un-pause via stacking-replace
    /// (which calls the same resume path) must leave the pending interruption's
    /// `.ended` recovery intact.
    func testConcurrentResume_doesNotDropPendingInterruption() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())

        postInterruption(.began)           // real interruption → _interrupted = true
        XCTAssertTrue(service.isPaused)

        // A racing manual resume (e.g. top-up dismiss) must not cancel the
        // pending interruption recovery.
        service.resumeAlarmSound()
        XCTAssertFalse(service.isPaused, "manual resume un-pauses")

        // The interruption still ends — recovery must run rather than no-op,
        // proving `_interrupted` survived the manual resume.
        let beforeEnded = service.sessionActivationCount
        postInterruption(.ended)
        XCTAssertEqual(
            service.sessionActivationCount, beforeEnded + 1,
            "interruption .ended must still reactivate — _interrupted must survive a concurrent resume (#395)"
        )
        XCTAssertEqual(service.state, .playing)

        service.stopAlarmSound()
    }

    /// Interruption began/ended round-trip must reactivate the session on
    /// `.ended` (#395) — the original #374 path, now routed through
    /// `resumePlaybackLocked`.
    func testInterruptionEnded_reactivatesSession() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())

        postInterruption(.began)
        let beforeEnded = service.sessionActivationCount
        postInterruption(.ended)
        XCTAssertEqual(
            service.sessionActivationCount, beforeEnded + 1,
            "interruption .ended must reclaim the session iOS tore down (#395)"
        )
        XCTAssertFalse(service.isPaused)
        XCTAssertEqual(service.state, .playing)

        service.stopAlarmSound()
    }

    // MARK: - The two failing lookups leave distinguishable traces (#765)
    //
    // Falling back to the synthetic tone is the behaviour and is unchanged;
    // what these pin is that the branch says so. Until #765 a user report of
    // "the alarm beeped instead of ringing" had nothing to grep: a missing
    // sound file, a build with no default sound, and a perfectly resolved
    // lookup were all equally silent. Only `AVAudioPlayer.init` failing — the
    // case where the file WAS found — left a line.

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)

    /// The real `default_alarm.caf` inside the test host (which IS the app
    /// bundle). Used as the file an injected lookup claims to have found, so
    /// `AVAudioPlayer` gets openable audio and the tests assert on a player
    /// built from a FILE rather than one built from in-memory WAV data.
    private func bundledDefaultAlarmURL() throws -> URL {
        try XCTUnwrap(
            Bundle.main.url(forResource: AudioService.fallbackSoundID, withExtension: "caf"),
            "the app bundle must carry its own fallback alarm sound"
        )
    }

    func testResolveAlarmPlayer_missingSoundWithFallbackPresent_logsTheDowngrade() throws {
        let fallbackURL = try bundledDefaultAlarmURL()
        var lines: [LoggedLine] = []
        let player = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            AudioService.shared.resolveAlarmPlayer(soundID: "vanished_sound") { name, ext in
                name == AudioService.fallbackSoundID && ext == "caf" ? fallbackURL : nil
            }
        })

        XCTAssertEqual(
            player?.url?.lastPathComponent, "default_alarm.caf",
            "the fallback file still answers — the alarm rings a real sound, not the synthetic tone"
        )

        let traces = lines.filter { $0.message.contains(AudioService.missingSoundErrorID) }
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
        // Literal, not `alarmSoundExtensions.joined(...)`: an expectation read
        // off the constant under test follows it wherever it goes and pins
        // nothing (#762). The docblock on that constant calls this substring
        // load-bearing — it is what separates "no such file" from "the file is
        // there under an extension this list does not know" — so it needs an
        // assertion of its own, or it is one deletion away from gone.
        XCTAssertTrue(
            traces.first?.message.contains("caf,m4a,wav,mp3") == true,
            "the line must say which extensions were tried; it reads «\(traces.first?.message ?? "")»"
        )
    }

    /// The branch the real bundle cannot reach — the app ships
    /// `default_alarm.caf`, so only an injected lookup can state its absence.
    /// `.fault`, not `.error`: this one is a defective build, not a degraded
    /// install of a correct one.
    func testResolveAlarmPlayer_nothingInTheBundle_logsTheBuildDefectAndStillFallsBackToTheTone() {
        var lines: [LoggedLine] = []
        let player = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            AudioService.shared.resolveAlarmPlayer(soundID: "vanished_sound") { _, _ in nil }
        })

        XCTAssertNotNil(player, "the synthetic tone is the last resort and #765 must not remove it")
        XCTAssertNil(
            player?.url,
            "a player carrying a file URL would mean the lookup did not actually fail"
        )

        let traces = lines.filter { $0.message.contains(AudioService.missingFallbackSoundErrorID) }
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
            lines.allSatisfy { !$0.message.contains(AudioService.missingSoundErrorID) },
            "the downgrade ID belongs to the branch where a real sound still rings; emitting both "
            + "here would make a support grep count one incident twice"
        )
        XCTAssertTrue(
            traces.first?.message.contains("caf,m4a,wav,mp3") == true,
            "the line must say which extensions were tried; it reads «\(traces.first?.message ?? "")»"
        )
    }

    /// The one behaviour this PR changes, and the only thing holding it.
    ///
    /// Before #765 the requested sound was looked up across all four
    /// extensions while the fallback tried `caf`/`m4a` only; both now walk
    /// ``AudioService/alarmSoundExtensions``. Nothing shipped depends on the
    /// widening — the bundle carries `default_alarm.caf`, which the first probe
    /// finds — so before this case existed, narrowing the list back to `["caf"]`
    /// left the whole file green while a default shipped as `.m4a` downgraded to
    /// the synthetic tone: the silent state #765 exists to make visible. That
    /// narrowing now reddens this case AND the two `caf,m4a,wav,mp3` assertions
    /// above, which read `tried` off the same list.
    ///
    /// The list is written out rather than read off the constant, for the same
    /// reason as the `caf,m4a,wav,mp3` assertions above.
    ///
    /// The injected URLs are deliberately unopenable: which branch was taken is
    /// decided before `AVAudioPlayer` is handed anything, and it is the branch —
    /// the emitted line — that is under test here, not the player.
    func testResolveAlarmPlayer_fallbackTriesEveryExtension_cafFirst() {
        for ext in ["caf", "m4a", "wav", "mp3"] {
            var lines: [LoggedLine] = []
            _ = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
                AudioService.shared.resolveAlarmPlayer(soundID: "vanished_sound") { name, probed in
                    name == AudioService.fallbackSoundID && probed == ext
                        ? URL(fileURLWithPath: "/var/empty/\(name).\(ext)")
                        : nil
                }
            })

            let downgrades = lines.filter { $0.message.contains(AudioService.missingSoundErrorID) }
            XCTAssertEqual(
                downgrades.count, 1,
                "a fallback shipped as .\(ext) has to be found; the sink saw \(lines.map(\.message))"
            )
            XCTAssertTrue(
                downgrades.first?.message.contains("default_alarm.\(ext)") == true,
                "the line must name the file the alarm falls back to; it reads "
                + "«\(downgrades.first?.message ?? "")»"
            )
            XCTAssertTrue(
                lines.allSatisfy { !$0.message.contains(AudioService.missingFallbackSoundErrorID) },
                "reporting «no default sound at all» for a default that IS there under .\(ext) "
                + "sends whoever greps it to rebuild a bundle that is fine"
            )
        }

        // Membership is not order. A lookup that answers for every extension
        // returns whichever one the loop reached first, and the line names it.
        var lines: [LoggedLine] = []
        _ = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            AudioService.shared.resolveAlarmPlayer(soundID: "vanished_sound") { name, ext in
                name == AudioService.fallbackSoundID
                    ? URL(fileURLWithPath: "/var/empty/\(name).\(ext)")
                    : nil
            }
        })
        // Filtered rather than `lines.first`, to match the loop above: an
        // unrelated line emitted earlier in the same call would otherwise break
        // this on a change that has nothing to do with probe order.
        let downgrade = lines.first { $0.message.contains(AudioService.missingSoundErrorID) }
        XCTAssertTrue(
            downgrade?.message.contains("default_alarm.caf") == true,
            "caf is probed first — the format the app actually ships; it reads «\(downgrade?.message ?? "")»"
        )
    }

    /// Silence is load-bearing on the path that works: this runs on every
    /// firing alarm, so a line here would put an `.error` in the log of a
    /// device where nothing is wrong.
    func testResolveAlarmPlayer_soundPresent_logsNothing() throws {
        let soundURL = try bundledDefaultAlarmURL()
        var lines: [LoggedLine] = []
        let player = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            // The lookup answers for the REQUESTED id, so the fallback branch
            // is never entered — which is the state under test.
            AudioService.shared.resolveAlarmPlayer(soundID: "radar") { name, ext in
                name == "radar" && ext == "caf" ? soundURL : nil
            }
        })

        XCTAssertNotNil(player, "a resolved lookup must produce a player")
        XCTAssertTrue(lines.isEmpty, "a resolved lookup must stay silent; the sink saw \(lines.map(\.message))")
    }

    /// Runs through the DEFAULT lookup — no injected `resourceURL` — so it
    /// asserts the production path all the way into `Bundle.main`.
    ///
    /// Without it the four cases above would all pass against a closure that
    /// was handed to them, i.e. they would test the stub. The test host IS the
    /// app bundle (`TEST_HOST`) and `default_alarm.caf` sits flat at its root,
    /// so emptying the default closure makes this red — both assertions: the
    /// lookup would find nothing, fall through to the synthetic tone (whose
    /// player carries no `url`) and log the `.fault`.
    func testResolveAlarmPlayer_resolvesTheBundledDefaultThroughTheRealBundle() {
        var lines: [LoggedLine] = []
        let player = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            AudioService.shared.resolveAlarmPlayer(soundID: AudioService.fallbackSoundID)
        })

        XCTAssertEqual(
            player?.url?.lastPathComponent, "default_alarm.caf",
            "the app bundle must carry its own fallback alarm sound — without it every alarm "
            + "beeps the synthetic tone"
        )
        XCTAssertTrue(
            lines.isEmpty,
            "resolving the bundled default is the working path and must stay silent; "
            + "the sink saw \(lines.map(\.message))"
        )
    }

    // MARK: - Playback volume (#766)

    // Before these, the word `volume` did not appear in this file at all: the
    // clamp inside `configurePlayerVolume` could have been replaced by
    // `player.volume = volume` with the whole suite still green. It is the
    // costliest of the `Alarm.clampedVolume` call sites, because it is the only
    // one on the playback path — a divergence there changes how loudly a real
    // alarm rings, not how a number is drawn.
    //
    // The fade-in branch stays unpinned on purpose. It seeds the player at `0`
    // and hands the clamped target to `setVolume(_:fadeDuration:)`, which the
    // audio thread reaches over 30 seconds; nothing readable within a unit test
    // distinguishes "clamped target" from "raw target" there. The non-fade
    // branch below writes the same clamped value synchronously, so the shared
    // expression is covered — what a fade-in-only regression would cost is a
    // ramp that lands on the wrong ceiling half a minute in.

    /// The plain case: an in-range volume must arrive on the player unchanged.
    /// Pins the wiring rather than the clamp — `startAlarmSound` has to reach
    /// `configurePlayerVolume` at all — and `0.4` is far enough from both the
    /// `1.0` default and the `0` a fade-in starts at that neither can fake it.
    func testStartAlarmSound_putsAnInRangeVolumeOnThePlayerUnchanged() {
        let service = AudioService.shared
        service.stopAlarmSound()

        service.startAlarmSound(soundID: "nonexistent_test_sound", volume: 0.4)

        XCTAssertEqual(
            service.state, .playing,
            "the volume assertion below only means something once a player is owned"
        )
        XCTAssertEqual(
            service.currentPlayerVolume, 0.4,
            "the requested volume never reached the player"
        )

        service.stopAlarmSound()
    }

    /// The branch the clamp exists for. A corrupt persisted `volume` must reach
    /// the speaker as *full* volume — never as silence, and never as the raw
    /// non-finite value, which is not a level any audio engine can honour. The
    /// one failure this app cannot have is an alarm nobody hears.
    ///
    /// Expectations are literals on purpose, not `Alarm.clampedVolume(seed)`:
    /// an oracle computed by the code under test agrees with any clamp,
    /// including no clamp at all.
    func testStartAlarmSound_clampsACorruptVolumeBeforeItReachesThePlayer() {
        let service = AudioService.shared

        for (seed, expected) in [(Float.nan, Float(1.0)), (Float(1.4), Float(1.0)), (Float(-0.2), Float(0.0))] {
            service.stopAlarmSound()
            service.startAlarmSound(soundID: "nonexistent_test_sound", volume: seed)

            XCTAssertEqual(service.state, .playing, "no player was owned for seed \(seed)")
            XCTAssertEqual(
                service.currentPlayerVolume, expected,
                "seed \(seed) reached the player as "
                + "\(String(describing: service.currentPlayerVolume)) instead of \(expected)"
            )
        }

        service.stopAlarmSound()
    }

    /// Pins the assumption the two out-of-range rows above rest on.
    ///
    /// `AVAudioPlayer.volume` documents the same `0.0…1.0` range `UISlider`
    /// has, and the seed test for the picker exists precisely because
    /// `UISlider` clamps an out-of-range assignment itself — reading a control
    /// that clamps is a green oracle for a screen that does not. Nothing says
    /// `AVAudioPlayer` behaves differently; it just happens not to today.
    ///
    /// If that changes, `1.4` and `-0.2` read back as `1.0` and `0.0` no
    /// matter what `startAlarmSound` did with them, the killer above collapses
    /// to the single `.nan` case, and nothing goes red to say so. This test is
    /// what goes red instead.
    func testAVAudioPlayerDoesNotClampVolumeItself() throws {
        let player = try XCTUnwrap(AudioService.generateAlarmTone())

        player.volume = 1.4

        XCTAssertEqual(
            player.volume, 1.4,
            """
            AVAudioPlayer now clamps its own volume, so the 1.4 and -0.2 rows \
            in testStartAlarmSound_clampsACorruptVolumeBeforeItReachesThePlayer \
            no longer distinguish a dropped clamp from a working one.
            """
        )
    }

    /// Nothing owned → nothing to report. Keeps the accessor from answering
    /// `0` for "stopped", which would leave every assertion above ambiguous
    /// between "clamped to zero" and "no player at all".
    func testCurrentPlayerVolume_isNilWhileStopped() {
        let service = AudioService.shared
        service.stopAlarmSound()

        XCTAssertNil(service.currentPlayerVolume)
    }

    /// The IDs are what a support ticket is grepped by, so telling the two
    /// states apart depends on them staying different strings.
    func testAlarmPlayerErrorIDs_areDistinct() {
        XCTAssertNotEqual(
            AudioService.missingSoundErrorID,
            AudioService.missingFallbackSoundErrorID,
            "a lost user sound and a build without a default sound must not grep as one thing"
        )
    }
}
