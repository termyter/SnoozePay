import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class EditorPriceCurrencyTests: XCTestCase {
    func testReusedCellRendersWalletUnitsWithoutChangingFractionalModel() throws {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        var changes: [Double] = []
        for code in ["USD", "EUR", "KWD", "RUB"] {
            cell.prepareForReuse()
            cell.onValueChanged = { changes.append($0) }
            cell.configure(amount: 49.5, currency: Currency(code: code)!)
            let field = try amountField(in: cell)
            XCTAssertEqual(field.text, "50")
            XCTAssertEqual(field.keyboardType, .numberPad)
            let spoken = code == "RUB" ? "Цена откладывания, рублей" : "Цена откладывания, \(code)"
            XCTAssertEqual(field.accessibilityLabel, spoken)
            XCTAssertTrue(labels(in: cell).contains { $0.text == (code == "RUB" ? "₽" : code) })
            XCTAssertTrue(labels(in: cell).contains { $0.text == "Минимум 1 \(code == "RUB" ? "₽" : code)" })
            XCTAssertTrue(changes.isEmpty, "Presentation must not commit money")
        }
    }

    func testCurrencyRefreshPreservesPendingInvalidInputSelectionAndCommitBoundary() throws {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        cell.configure(amount: 50, currency: .rub)
        let field = try amountField(in: cell)
        var changes: [Double] = []
        cell.onValueChanged = { changes.append($0) }
        field.text = "1.5"
        field.sendActions(for: .editingChanged)
        let start = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: 1))
        let end = try XCTUnwrap(field.position(from: start, offset: 1))
        field.selectedTextRange = field.textRange(from: start, to: end)
        cell.updateCurrency(Currency(code: "USD")!)
        XCTAssertEqual(field.text, "1.5")
        let selection = try XCTUnwrap(field.selectedTextRange)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 1)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.end), 2)
        let helper = try XCTUnwrap(labels(in: cell).first { $0.text == "Минимум 1 USD" })
        XCTAssertFalse(helper.isHidden)
        XCTAssertTrue(changes.isEmpty)
        field.sendActions(for: .editingDidEnd)
        XCTAssertEqual(field.text, "50", "Invalid input must retain the prior trusted amount")
        field.text = "137"
        field.sendActions(for: .editingChanged)
        cell.updateCurrency(Currency(code: "EUR")!)
        XCTAssertEqual(field.text, "137")
        XCTAssertTrue(changes.isEmpty)
        field.sendActions(for: .editingDidEnd)
        XCTAssertEqual(changes, [137])
    }

    func testActualCreateAndEditSaveUntouchedRawFractionalPriceInWalletUnits() throws {
        for editing in [false, true] {
            let fixture = makeSUT(editing: editing)
            let sut = fixture.controller
            let indexPath = IndexPath(row: 0, section: CreateAlarmViewController.Section.penalty.rawValue)
            let cell = sut.makePenaltyCell(sut.tableView, at: indexPath)
            XCTAssertEqual(try amountField(in: cell).text, "50")
            XCTAssertTrue(labels(in: cell).contains { $0.text == "USD" })
            XCTAssertEqual(sut.viewModel.penaltyAmount, 49.5)
            let save = try XCTUnwrap(sut.saveButton)
            XCTAssertTrue(save.isEnabled)
            var didSave = false
            sut.onSave = { didSave = true }
            save.sendActions(for: .touchUpInside)
            XCTAssertTrue(didSave)
            let saved = try fixture.repository.fetchAllChecked()
            XCTAssertEqual(saved.count, 1)
            XCTAssertEqual(saved.first?.penaltyAmount, 49.5)
        }
    }

    func testReappearanceUpdatesMountedLabelsWithoutReloadingPendingInput() throws {
        let fixture = makeSUT(currency: nil)
        let sut = fixture.controller
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = sut
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()
        let indexPath = IndexPath(row: 0, section: CreateAlarmViewController.Section.penalty.rawValue)
        sut.tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        sut.tableView.layoutIfNeeded()
        let initial = try XCTUnwrap(sut.tableView.cellForRow(at: indexPath))
        let field = try amountField(in: initial)
        XCTAssertEqual(field.accessibilityLabel, "Цена откладывания, рублей")
        field.text = "137"
        field.sendActions(for: .editingChanged)
        let usd = try XCTUnwrap(Currency(code: "USD"))
        XCTAssertEqual(fixture.wallet.freezeCurrency(usd), .frozen(usd))
        sut.viewWillAppear(false)
        sut.tableView.layoutIfNeeded()
        let refreshed = try XCTUnwrap(sut.tableView.cellForRow(at: indexPath))
        XCTAssertTrue(refreshed === initial)
        XCTAssertEqual(try amountField(in: refreshed).text, "137")
        XCTAssertEqual(field.accessibilityLabel, "Цена откладывания, USD")
        XCTAssertTrue(labels(in: refreshed).contains { $0.text == "USD" })
        XCTAssertEqual(sut.viewModel.penaltyAmount, 49.5)
    }

    private struct Fixture {
        let controller: CreateAlarmViewController
        let repository: AlarmRepository
        let wallet: BalanceService
    }

    private func makeSUT(
        editing: Bool = false, currency: Currency? = Currency(code: "USD")!
    ) -> Fixture {
        let suite = "test.editor.currency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let repository = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())
        let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        if let currency { XCTAssertEqual(wallet.freezeCurrency(currency), .frozen(currency)) }
        let alarmDefaults = AlarmDefaults(defaults: defaults)
        alarmDefaults.penaltyAmount = 49.5
        let alarm = editing ? Alarm(penaltyAmount: 49.5) : nil
        if let alarm { XCTAssertTrue(repository.save(alarm)) }
        let viewModel = CreateAlarmViewModel(
            alarm: alarm, repository: repository, defaults: alarmDefaults, balanceService: wallet
        )
        let sut = CreateAlarmViewController(viewModel: viewModel)
        sut.loadViewIfNeeded()
        return Fixture(controller: sut, repository: repository, wallet: wallet)
    }

    private func amountField(in view: UIView) throws -> UITextField {
        try XCTUnwrap(descendants(in: view).compactMap { $0 as? UITextField }.first {
            $0.accessibilityIdentifier == "createAlarm.penaltyField"
        })
    }

    private func labels(in view: UIView) -> [UILabel] { descendants(in: view).compactMap { $0 as? UILabel } }
    private func descendants(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }

    private final class NoopScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }
}
