import XCTest
@testable import SnoozePay

/// `AudioService` posts its notifications from main, after its serial queue
/// has been released (#848).
///
/// Before the fix, `stateChangedNotification` was posted from the `_state`
/// `didSet`, inside `queue.sync`. `NotificationCenter.post` waits until a block
/// observer on an `OperationQueue` has run, and the firing screen observes with
/// `queue: .main`. So a transition driven from a background thread held the
/// audio queue until main ran the block. If main was in any `queue.sync` of
/// the service at that moment, neither side could move: the app froze on the
/// ringing screen.
///
/// None of these cases can hang the suite when the fix is reverted. Main is
/// never made to wait on the audio queue itself, only on a semaphore with a
/// timeout, so a regression shows up as a red assertion within seconds.
///
/// Its own file rather than more cases in `AudioServiceTests`, which is
/// already past 900 lines.
final class AudioServiceNotificationDeliveryTests: XCTestCase {

    /// One delivered `stateChangedNotification`, as the observer saw it. A
    /// tuple rather than a struct: the observer block below is not on the
    /// main actor, and under this target's default isolation a struct's
    /// initializer would be.
    private typealias Delivery = (state: AudioPlaybackState?, onMain: Bool, fromService: Bool)

    /// The background call a helper drives. An enum rather than a closure
    /// parameter, so each call stays inside a `DispatchQueue` block like the
    /// rest of this suite's background calls.
    private enum Transition {
        case start, stop
    }

    private var observers: [NSObjectProtocol] = []

    override func setUp() {
        super.setUp()
        AudioService.shared.stopAlarmSound()
        // Spend posts that earlier tests' transitions left on the main queue,
        // so none of them lands in this test's observer.
        drainMainQueue()
    }

    override func tearDown() {
        // Observers go first: the stop below posts one more `.stopped`, and a
        // block left registered would outlive the test (the PR #846 lesson).
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
        super.tearDown()
    }

    // MARK: - The deadlock shape

    /// A background stop must return while main is busy and not running its
    /// queue.
    ///
    /// This is the #848 deadlock with one substitution. In the app, main is
    /// held inside an `AudioService` read (`queue.sync`) that waits for the
    /// audio queue, which is waiting for main. Here main is held on a
    /// semaphore instead. The audio side is identical: a stop from a
    /// background thread with a `queue: .main` observer registered. The
    /// semaphore has a timeout, so a synchronous post turns this red after
    /// two seconds instead of freezing the run.
    func testBackgroundStop_returnsWhileMainIsHeld() {
        let service = AudioService.shared
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
        XCTAssertNotEqual(service.state, .stopped, "test precondition: the stop below has to be a transition")
        drainMainQueue()

        assertReturnsWhileMainIsHeld(.stop)
    }

    /// Same shape for a start. `startAlarmSound` can arrive on a UN-delegate
    /// background thread (see the doc on the service's `queue`).
    func testBackgroundStart_returnsWhileMainIsHeld() {
        XCTAssertEqual(
            AudioService.shared.state, .stopped,
            "test precondition: the start below has to be a transition"
        )

        assertReturnsWhileMainIsHeld(.start)
    }

    // MARK: - What observers receive

    /// Transitions driven from a background thread reach observers on main,
    /// with the service as `object` and each state in `userInfo`, in the
    /// order they happened. The observer uses `queue: nil`, so it runs on the
    /// posting thread and records where the post really came from.
    func testBackgroundTransitions_areDeliveredOnMainInOrderWithTheirState() {
        let service = AudioService.shared
        var deliveries: [Delivery] = []
        observers.append(NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: nil,
            queue: nil
        ) { note in
            deliveries.append((
                state: note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState,
                onMain: Thread.isMainThread,
                fromService: (note.object as? AudioService) === service
            ))
        })

        let done = expectation(description: "background start/stop cycles returned")
        DispatchQueue.global(qos: .userInitiated).async {
            service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
            service.stopAlarmSound()
            service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
            service.stopAlarmSound()
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        drainMainQueue()

        let states = deliveries.map { $0.state }
        let started = states.first ?? nil
        XCTAssertNotNil(started, "nothing was delivered, or a delivery lost its userInfo state")
        XCTAssertNotEqual(started, .stopped, "the first delivery must be the start's state")
        XCTAssertEqual(
            states, [started, .stopped, started, .stopped],
            "every transition must be delivered once, in the order it happened"
        )
        XCTAssertTrue(
            deliveries.allSatisfy { $0.onMain },
            "a state notification was posted off main, i.e. from the thread that held the audio queue"
        )
        XCTAssertTrue(
            deliveries.allSatisfy { $0.fromService },
            "the notification's object must stay the service"
        )
        XCTAssertEqual(states.last ?? nil, service.state, "the last delivered state must be the current one")
    }

    /// A main-thread transition is not delivered inside the call that made it.
    /// It arrives on a later main-queue turn, after `queue` is free. That is
    /// what lets an observer read the service back without a nested
    /// `queue.sync`, and why `AlarmFiringViewController.viewDidLoad` reads
    /// `state` itself right after `startAlarmSound`.
    func testMainThreadTransition_isDeliveredAfterTheCallReturns() {
        let service = AudioService.shared
        var deliveries: [Delivery] = []
        observers.append(NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: nil,
            queue: nil
        ) { note in
            deliveries.append((
                state: note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState,
                onMain: Thread.isMainThread,
                fromService: (note.object as? AudioService) === service
            ))
        })

        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
        let startedState = service.state
        XCTAssertTrue(
            deliveries.isEmpty,
            "the post ran inside startAlarmSound, i.e. while the audio queue was still held"
        )

        drainMainQueue()
        XCTAssertEqual(
            deliveries.map { $0.state }, [startedState],
            "one delivery, carrying the state that was set"
        )
        XCTAssertEqual(deliveries.first?.onMain, true)
        XCTAssertEqual(deliveries.first?.fromService, true)
    }

    // MARK: - Helpers

    /// Run `transition` on a background thread while main is blocked on a
    /// semaphore, and fail if it does not return within two seconds.
    ///
    /// A `queue: .main` observer is registered for the duration, the way the
    /// firing screen's is. A post that waits for that observer cannot finish
    /// while main is blocked, so the call would not return.
    ///
    /// After the bounded wait, main runs its loop until the call has
    /// returned. That lets a synchronous post (the regression) finish, so the
    /// failure stays a failure and does not leave a stuck thread for the
    /// next test. The delivery is checked last, after a drain, to show the
    /// main observer still got exactly one post.
    private func assertReturnsWhileMainIsHeld(
        _ transition: Transition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let service = AudioService.shared
        var delivered: [AudioPlaybackState?] = []
        observers.append(NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: service,
            queue: .main
        ) { note in
            delivered.append(note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState)
        })

        let returned = DispatchSemaphore(value: 0)
        let finished = expectation(description: "background \(transition) returned")
        DispatchQueue.global(qos: .userInitiated).async {
            switch transition {
            case .start:
                service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
            case .stop:
                service.stopAlarmSound()
            }
            returned.signal()
            finished.fulfill()
        }

        // Main is not running its queue during this wait, so the `.main`
        // observer cannot run either.
        let whileHeld = returned.wait(timeout: .now() + 2)
        wait(for: [finished], timeout: 10)

        XCTAssertEqual(
            whileHeld, .success,
            """
            a background \(transition) did not return while main was busy: its state \
            notification was posted inside the audio queue and waited for main to run the \
            observer. Had main been in AudioService.state instead of on a semaphore, the app \
            would have deadlocked (#848).
            """,
            file: file, line: line
        )

        drainMainQueue()
        XCTAssertEqual(
            delivered, [service.state],
            "the main observer must see the transition once, with the state it landed in",
            file: file, line: line
        )
    }
}
