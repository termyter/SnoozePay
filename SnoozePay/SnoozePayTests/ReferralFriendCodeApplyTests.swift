import UIKit
import XCTest
@testable import SnoozePay

/// The «Код друга» card on `ReferralViewController` redeems through the real
/// `ReferralService` (#1088). Before, «Применить» showed «Код применён» without
/// calling the service: no stored code, no credit, no ledger row (#701).
///
/// Each case drives the screen's own text field and apply button against a
/// service on an isolated `UserDefaults` suite, then checks both what the screen
/// reports and what the store really holds — a confirmation is only correct if
/// the store agrees with it.
@MainActor
final class ReferralFriendCodeApplyTests: XCTestCase {

    private var suiteNames: [String] = []

    override func tearDown() {
        suiteNames.forEach { UserDefaults().removePersistentDomain(forName: $0) }
        suiteNames.removeAll()
        super.tearDown()
    }

    // MARK: - Success

    func testValidCodeCreditsThroughServiceAndReportsTheCreditedAmount() throws {
        let store = try makeStore(balance: 0)
        let screen = makeScreen(service: store.service)

        try enter("  abcd23 ", in: screen)
        try applyButton(in: screen.controller).sendActions(for: .touchUpInside)

        XCTAssertEqual(store.defaults.string(forKey: "referral_applied_code"), "ABCD23")
        XCTAssertEqual(promotions(in: store.defaults).map(\.amount), [ReferralService.referralBonusAmount],
                       "Exactly one referral credit must land in the ledger")
        XCTAssertEqual(store.wallet.balance, ReferralService.referralBonusAmount)

        let alert = try XCTUnwrap(screen.alerts.single)
        XCTAssertEqual(alert.title, Localized.text("referral.applied.title"))
        XCTAssertEqual(alert.message, Localized.format("referral.hint.bonus_credited",
                                                       MoneyFormatter.string(ReferralService.referralBonusAmount)))
        XCTAssertEqual(alert.actions.map(\.title), [Localized.text("common.button.ok")])
        try assertLocked(screen)
    }

    // MARK: - Rejections

    func testInvalidFormatReportsTheServiceReasonAndChangesNothing() throws {
        let store = try makeStore(balance: 300)
        let before = store.domain
        let screen = makeScreen(service: store.service)

        // The old placeholder example: ten characters with a hyphen, which the
        // service has never accepted.
        try enter("WAKEUP-7K2", in: screen)
        try applyButton(in: screen.controller).sendActions(for: .touchUpInside)

        try assertRejected(screen, reason: ReferralService.ApplyError.invalidFormat.errorDescription)
        XCTAssertEqual(store.domain as NSDictionary, before as NSDictionary,
                       "A rejected apply must not write the referral or money store")
    }

    func testOwnCodeIsRejectedWithoutCredit() throws {
        let store = try makeStore(balance: 300, myCode: "JKLM23")
        let before = store.domain
        let screen = makeScreen(service: store.service)

        try enter("jklm23", in: screen)
        try applyButton(in: screen.controller).sendActions(for: .touchUpInside)

        try assertRejected(screen, reason: ReferralService.ApplyError.cannotApplyOwnCode.errorDescription)
        XCTAssertEqual(store.domain as NSDictionary, before as NSDictionary)
    }

    func testUnexpectedErrorReportsGenericFailureWithoutLocking() throws {
        struct Unexpected: Error {}
        let screen = makeScreen(
            applier: { _ in throw Unexpected() },
            appliedCode: { nil }
        )

        try enter("ABCD23", in: screen)
        try applyButton(in: screen.controller).sendActions(for: .touchUpInside)

        try assertRejected(screen, reason: nil)
    }

    // MARK: - Already applied

    func testCodeAppliedEarlierLocksTheInputOnOpen() throws {
        let store = try makeStore(balance: 300, appliedCode: "XYZ789")
        var applies = 0
        let screen = makeScreen(
            applier: { applies += 1; return try store.service.applyFriendCode($0) },
            appliedCode: { store.service.appliedFriendCode }
        )
        screen.controller.loadViewIfNeeded()

        try assertLocked(screen)
        XCTAssertEqual(applies, 0)
        XCTAssertTrue(screen.alerts.items.isEmpty)
    }

    func testSecondApplyAfterSuccessIsNotOffered() throws {
        let store = try makeStore(balance: 0)
        let screen = makeScreen(service: store.service)
        try enter("ABCD23", in: screen)
        try applyButton(in: screen.controller).sendActions(for: .touchUpInside)

        let reopened = makeScreen(service: ReferralService(
            defaults: store.defaults, balanceService: makeWallet(defaults: store.defaults)
        ))
        reopened.controller.loadViewIfNeeded()

        try assertLocked(reopened)
        XCTAssertEqual(promotions(in: store.defaults).count, 1)
    }

    // MARK: - Assertions

    private func assertRejected(_ screen: Screen, reason: String?,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let alert = try XCTUnwrap(screen.alerts.single, file: file, line: line)
        XCTAssertEqual(alert.title, Localized.text("referral.error.apply_failed"), file: file, line: line)
        XCTAssertEqual(alert.message, reason, file: file, line: line)
        XCTAssertNotEqual(alert.title, Localized.text("referral.applied.title"),
                          "A rejection must never read as «code applied»", file: file, line: line)
        let field = try textField(in: screen.controller)
        XCTAssertTrue(field.isEnabled, "A rejected code must stay editable for a retry", file: file, line: line)
        XCTAssertTrue(try applyButton(in: screen.controller).isEnabled, file: file, line: line)
    }

    private func assertLocked(_ screen: Screen, file: StaticString = #filePath, line: UInt = #line) throws {
        let field = try textField(in: screen.controller)
        XCTAssertFalse(field.isEnabled, file: file, line: line)
        XCTAssertEqual(field.text ?? "", "", file: file, line: line)
        XCTAssertEqual(field.placeholder, Localized.text("referral.row.already_applied"), file: file, line: line)
        XCTAssertFalse(try applyButton(in: screen.controller).isEnabled, file: file, line: line)
    }

    // MARK: - Screen

    private struct Screen {
        let controller: ReferralViewController
        let alerts: AlertCapture
    }

    private final class AlertCapture {
        private(set) var items: [UIAlertController] = []
        var single: UIAlertController? { items.count == 1 ? items[0] : nil }
        func record(_ alert: UIAlertController) { items.append(alert) }
    }

    private func makeScreen(service: ReferralService) -> Screen {
        makeScreen(applier: { try service.applyFriendCode($0) }, appliedCode: { service.appliedFriendCode })
    }

    private func makeScreen(
        applier: @escaping ReferralViewController.FriendCodeApplier,
        appliedCode: @escaping () -> String?
    ) -> Screen {
        let alerts = AlertCapture()
        let controller = ReferralViewController(
            personalCodeProvider: { "QRST45" },
            friendCodeApplier: applier,
            appliedFriendCodeProvider: appliedCode,
            presentAlert: { _, alert in alerts.record(alert) },
            pasteboard: UIPasteboard.withUniqueName()
        )
        return Screen(controller: controller, alerts: alerts)
    }

    /// Types through the field's own editing event, which is what enables the
    /// apply button on screen.
    private func enter(_ text: String, in screen: Screen) throws {
        screen.controller.loadViewIfNeeded()
        let field = try textField(in: screen.controller)
        XCTAssertTrue(field.isEnabled)
        field.text = text
        field.sendActions(for: .editingChanged)
        XCTAssertTrue(try applyButton(in: screen.controller).isEnabled)
    }

    private func textField(in controller: UIViewController) throws -> UITextField {
        try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UITextField }.first)
    }

    private func applyButton(in controller: UIViewController) throws -> SPButton {
        try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? SPButton }
            .first { $0.accessibilityLabel == Localized.text("referral.button.apply") })
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    // MARK: - Store

    private struct Store {
        let name: String
        let defaults: UserDefaults
        let wallet: BalanceService
        let service: ReferralService

        var domain: [String: Any] { defaults.persistentDomain(forName: name) ?? [:] }
    }

    private func makeStore(balance: Double, myCode: String? = nil, appliedCode: String? = nil) throws -> Store {
        let name = "test.referral.friend-code-apply.\(UUID().uuidString)"
        suiteNames.append(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(balance, forKey: "user_balance")
        if let myCode { defaults.set(myCode, forKey: "referral_my_code") }
        if let appliedCode { defaults.set(appliedCode, forKey: "referral_applied_code") }
        let wallet = makeWallet(defaults: defaults)
        return Store(name: name, defaults: defaults, wallet: wallet,
                     service: ReferralService(defaults: defaults, balanceService: wallet))
    }

    private func makeWallet(defaults: UserDefaults) -> BalanceService {
        let repository = TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults))
        return BalanceService(defaults: defaults, transactionRepository: repository,
                              notificationCenter: NotificationCenter())
    }

    private func promotions(in defaults: UserDefaults) -> [Transaction] {
        TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults))
            .fetchAllOrFail().filter { $0.type == .promotion }
    }
}
