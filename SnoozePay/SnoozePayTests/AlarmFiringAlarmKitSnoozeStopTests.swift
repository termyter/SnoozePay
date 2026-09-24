import os
import UIKit
import XCTest
@testable import SnoozePay

/// #880: `dismissAfterAlarmKitSnooze` checks the audio owner and stops in one
/// step, and says so when it leaves another alarm's sound alone.
///
/// It used to read `currentAlarmID` and then call `stopAlarmSound()`, with no
/// else: a skipped stop left nothing in the log. The screen here is on the
/// AlarmKit path, so `viewDidLoad` never starts the sound; the ring is the
/// shared service started by hand on the synthetic tone, as
/// `AudioServiceOwnerGatedStopTests.ring` does. The view is never loaded, so
/// no ticker or observer outlives the test. Nothing here touches
/// `UserDefaults` (#814). Setup and teardown stop the sound and drain main, so
/// no post queued here or earlier leaks across tests (#618, #846).
@MainActor
final class AlarmFiringAlarmKitSnoozeStopTests: XCTestCase {

    /// A sound id with no file behind it, so the service plays the synthetic
    /// tone: the bundle's files are not what this pins.
    private static let toneSoundID = "nonexistent_test_sound"

    override func setUp() {
        super.setUp()
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
    }

    /// Another alarm owns the sound: the screen keeps it ringing and writes
    /// one line naming both alarms by their 8-hex handle.
    func testAnotherAlarmOwnsTheSound_keepsItAndNamesBothHandles() {
        let alarm = Alarm(name: "Работа", snoozeMinutes: 5, penaltyAmount: 50)
        let ownerID = UUID()
        defer {
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }
        let screen = makeScreen(for: alarm)
        ring(ownerID)

        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            screen.dismissAfterAlarmKitSnooze()
        })

        XCTAssertEqual(AudioService.shared.currentAlarmID, ownerID, "the snooze's dismiss took another alarm's sound")
        XCTAssertEqual(AudioService.shared.state, .playing, "the snooze's dismiss silenced another alarm")
        XCTAssertEqual(lines.count, 1, "\(lines.map(\.message))")
        let line = lines.first
        XCTAssertEqual(line?.category, .audio)
        XCTAssertEqual(line?.level, .default)
        XCTAssertEqual(
            line?.message,
            "dismissAfterAlarmKitSnooze: skip stop — owner=\(handle(ownerID)), ours=\(handle(alarm.id))"
        )
    }

    /// The screen's own alarm owns the sound: it is stopped, and a stop that
    /// happened is not news.
    func testThisAlarmOwnsTheSound_stopsItWithoutALine() {
        let alarm = Alarm(name: "Работа", snoozeMinutes: 5, penaltyAmount: 50)
        defer {
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }
        let screen = makeScreen(for: alarm)
        ring(alarm.id)

        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            screen.dismissAfterAlarmKitSnooze()
        })

        XCTAssertEqual(AudioService.shared.state, .stopped, "the screen's own sound kept ringing")
        XCTAssertNil(AudioService.shared.currentAlarmID, "the stop left an owner behind")
        XCTAssertTrue(lines.isEmpty, "\(lines.map(\.message))")
    }

    // MARK: - Helpers

    /// A firing screen on the AlarmKit path, view not loaded: only the method
    /// under test runs.
    private func makeScreen(for alarm: Alarm) -> AlarmFiringViewController {
        let viewModel = AlarmFiringViewModel(
            alarm: alarm,
            balanceService: SnoozeStopWallet(),
            scheduler: AlarmScheduler(
                notificationCenter: InertNotificationCenter(),
                alarmKit: TestAlarmKitBackend()
            )
        )
        XCTAssertTrue(viewModel.usesAlarmKit, "test precondition: the screen must be on the AlarmKit path")
        return AlarmFiringViewController(viewModel: viewModel)
    }

    private func ring(_ alarmID: UUID, file: StaticString = #filePath, line: UInt = #line) {
        AudioService.shared.startAlarmSound(soundID: Self.toneSoundID, alarmID: alarmID)
        XCTAssertEqual(
            AudioService.shared.currentAlarmID, alarmID, "test precondition: the alarm has to own the sound",
            file: file, line: line
        )
        XCTAssertEqual(
            AudioService.shared.state, .playing, "test precondition: the alarm has to be audible",
            file: file, line: line
        )
    }

    private func handle(_ alarmID: UUID) -> String { String(alarmID.uuidString.prefix(8)) }
}

/// A funded wallet that is never charged: nothing here snoozes.
private final class SnoozeStopWallet: AlarmFiringBalancing {
    var balance: Double { 1000 }
    func canAfford(_ amount: Double) -> Bool { true }
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? { nil }
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool { false }
}
