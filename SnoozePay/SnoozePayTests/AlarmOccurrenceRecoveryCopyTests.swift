import UIKit
import XCTest
@testable import SnoozePay

/// Owns finish/recovery copy independently of the editor's source partition.
/// The source scan finds unpinned additions; the literal table pins both
/// translations; the real consumers below catch a correct key at a wrong site.
@MainActor
final class AlarmOccurrenceRecoveryCopyTests: XCTestCase {
    private static let sources = [
        "ViewControllers/Alarms/AlarmOccurrenceRecoveryAlerts.swift",
        "ViewControllers/Alarms/AlarmFiringViewController+OccurrenceRecovery.swift",
        "ViewControllers/Alarms/AlarmsOccurrenceRecoveryHeader.swift",
        "Views/AlarmFinishRecoveryPanel.swift"
    ]
    private static let copy: [String: (ru: String, en: String)] = [
        "firing.finish.error.message": (
            "Не удалось подтвердить выключение будильника. Попробуйте ещё раз. Платное откладывание пока недоступно.",
            "Could not confirm that the alarm stopped. Try again. Paid snoozing is temporarily unavailable."
        ),
        "firing.finish.error.title": ("Завершение не подтверждено", "Finish not confirmed"),
        "firing.finish.retry": ("Повторить", "Try Again"),
        "firing.finish.recovery.confirmed": ("Завершение подтверждено", "Finish Confirmed"),
        "firing.finish.recovery.message": (
            "После перезапуска можно повторно подтвердить завершение. При успехе подъём отмечается текущим временем. "
                + "Новое срабатывание не выключается.",
            "You can confirm the pending finish after restarting. "
                + "A successful retry records a wake at the current time. It does not stop a new alarm."
        ),
        "firing.finish.recovery.previous": ("Проверить предыдущую попытку", "Check Previous Finish"),
        "firing.finish.recovery.retry": ("Повторить завершение", "Confirm Pending Finish"),
        "firing.finish.recovery.title": ("Незавершённая попытка", "Pending finish"),
        "firing.finish.recovery.unavailable": (
            "Не удалось прочитать незавершённые попытки. Данные сохранены. Попробуйте ещё раз.",
            "Could not read pending finishes. Your data is preserved. Try again."
        )
    ]
    // FiringCopyTests already pins the shared close button's words. It remains
    // part of this source inventory and the consumer assertions below.
    private static let pinnedElsewhere: Set<String> = ["common.button.close"]

    func testCopyTableHoldsExactlyTheKeysTheRecoverySourcesRead() {
        let reading = CatalogueKeyScanner.read(Self.sources, under: Self.appSourceRoot())
        XCTAssertEqual(reading.unreadable, [], "A moved source must not silently shrink copy coverage")
        XCTAssertFalse(reading.keys.isEmpty)
        XCTAssertEqual(reading.keys.subtracting(Self.pinnedElsewhere), Set(Self.copy.keys))
        XCTAssertEqual(Self.pinnedElsewhere.subtracting(reading.keys), [])
    }

    func testAcceptedRussianAndEnglishCopyRemainPinnedAndRussianKeysResolve() throws {
        let data = try Data(contentsOf: Self.appSourceRoot().appendingPathComponent("Resources/Localizable.xcstrings"))
        let catalogue = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalogue["strings"] as? [String: Any])
        for (key, expected) in Self.copy {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for (language, words) in [("ru", expected.ru), ("en", expected.en)] {
                let localization = try XCTUnwrap(localizations[language] as? [String: Any], "\(key): \(language)")
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: String], key)
                XCTAssertEqual(unit["value"], words, "\(key): \(language)")
                XCTAssertEqual(unit["state"], "translated", "\(key): \(language)")
            }
            XCTAssertEqual(Localized.text(key), expected.ru, key)
            XCTAssertNotNil(Localized.optionalText(key), key)
        }
    }

    func testPendingPanelRendersConfirmationSemanticsAndNamesItsExactAction() {
        let ticket = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: UUID(), token: nil)
        let panel = AlarmFinishRecoveryPanel()
        panel.configure(entries: [.init(ticket: ticket, alarmName: "Работа")], unavailable: false)

        XCTAssertEqual(panel.arrangedSubviews.compactMap { ($0 as? UILabel)?.text }, [
            Self.copy["firing.finish.recovery.title"]!.ru,
            Self.copy["firing.finish.recovery.message"]!.ru,
            "Работа"
        ])
        XCTAssertEqual(panel.retryButtons.map { $0.title(for: .normal) }, ["Повторить завершение"])
        XCTAssertEqual(panel.retryButtons.first?.accessibilityLabel, "Повторить завершение. Работа")
        XCTAssertEqual(panel.retryButtons.first?.accessibilityIdentifier,
                       "alarmFinishRecovery.retry.\(ticket.id.uuidString)")
    }

    func testUnavailablePanelUsesReloadCopyRatherThanAConfirmationAction() {
        let panel = AlarmFinishRecoveryPanel()
        panel.configure(entries: [], unavailable: true)

        XCTAssertEqual(panel.arrangedSubviews.compactMap { ($0 as? UILabel)?.text }, [
            "Незавершённая попытка",
            "Не удалось прочитать незавершённые попытки. Данные сохранены. Попробуйте ещё раз."
        ])
        XCTAssertEqual(panel.retryButtons.map { $0.title(for: .normal) }, ["Повторить"])
        XCTAssertEqual(panel.retryButtons.first?.accessibilityIdentifier, "alarmFinishRecovery.reload")
    }

    func testQuietRecoveryAlertsRenderUnconfirmedFailureAndConfirmedSuccessSeparately() throws {
        let ticket = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: UUID(), token: nil)
        let recovery = CopyRecoveryStub()
        let host = CopyAlertHost()
        AlarmOccurrenceRecoveryAlerts.perform(ticket, on: host, recovery: recovery)
        let failure = try XCTUnwrap(host.presentations.last as? UIAlertController)
        XCTAssertEqual(failure.title, "Завершение не подтверждено")
        XCTAssertEqual(failure.message,
                       "Не удалось подтвердить выключение будильника. Попробуйте ещё раз. "
                           + "Платное откладывание пока недоступно.")
        XCTAssertEqual(failure.actions.map(\.title), ["Повторить", "Закрыть"])

        recovery.result = .success(.completedNow)
        AlarmOccurrenceRecoveryAlerts.perform(ticket, on: host, recovery: recovery)
        let success = try XCTUnwrap(host.presentations.last as? UIAlertController)
        XCTAssertEqual(success.title, "Завершение подтверждено")
        XCTAssertNil(success.message)
        XCTAssertEqual(success.actions.map(\.title), ["Закрыть"])
        XCTAssertEqual(recovery.requests, [ticket, ticket])
    }

    func testNewFiringErrorNamesItsOwnRetryAndPreviousAttemptSeparately() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        _ = try fixture.recoveryTrackedTicket()
        let screen = CopyFiringHost(viewModel: fixture.model())
        screen.occurrenceRecovery = fixture.recoveryService()

        screen.presentOccurrenceFinishError(.nativeUnconfirmed)

        let alert = try XCTUnwrap(screen.presentations.last as? UIAlertController)
        XCTAssertEqual(alert.title, "Завершение не подтверждено")
        XCTAssertEqual(alert.message,
                       "Не удалось подтвердить выключение будильника. Попробуйте ещё раз. "
                           + "Платное откладывание пока недоступно.")
        XCTAssertEqual(alert.actions.map(\.title), ["Повторить", "Проверить предыдущую попытку", "Закрыть"])
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
    }

    private static func appSourceRoot(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SnoozePay")
    }
}

@MainActor
private final class CopyRecoveryStub: AlarmOccurrenceRecovering {
    var result: Result<AlarmOccurrenceFinishOutcome, AlarmOccurrenceFinishError> = .failure(.nativeUnconfirmed)
    private(set) var requests: [AlarmOccurrenceFinishTicket] = []
    func pendingFinishes() throws -> [AlarmOccurrenceRecoveryEntry] { [] }
    func resume(
        _ ticket: AlarmOccurrenceFinishTicket
    ) -> Result<AlarmOccurrenceFinishOutcome, AlarmOccurrenceFinishError> {
        requests.append(ticket)
        return result
    }
}

@MainActor
private final class CopyAlertHost: UIViewController {
    private(set) var presentations: [UIViewController] = []
    override func present(_ controller: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentations.append(controller)
        completion?()
    }
}

@MainActor
private final class CopyFiringHost: AlarmFiringViewController {
    private(set) var presentations: [UIViewController] = []
    override func present(_ controller: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentations.append(controller)
        completion?()
    }
}
