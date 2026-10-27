import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class ReferralPersonalCodeTests: XCTestCase {
    private struct Screen {
        let controller: ReferralViewController
        let pasteboard: UIPasteboard
        let share: ReferralPersonalCodeShareCapture
    }

    private struct Store {
        let name: String
        let defaults: UserDefaults
        let service: ReferralService

        var domain: [String: Any] { defaults.persistentDomain(forName: name) ?? [:] }
    }

    private var windows: [UIWindow] = []
    private var pasteboardNames: [UIPasteboard.Name] = []
    private var stores: [Store] = []

    override func tearDown() {
        for window in windows {
            window.rootViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
        windows.removeAll()
        pasteboardNames.forEach { UIPasteboard.remove(withName: $0) }
        pasteboardNames.removeAll()
        stores.forEach { $0.defaults.removePersistentDomain(forName: $0.name) }
        stores.removeAll()
        super.tearDown()
    }

    func testCodeResolvesLazilyAndCopyShareKeepTheDisplayedSnapshot() throws {
        let appDomain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let before = UserDefaults.standard.persistentDomain(forName: appDomain) ?? [:]
        var providerCalls = 0
        let screen = makeScreen {
            providerCalls += 1
            return providerCalls == 1 ? "ABCD23" : "XYZ789"
        }
        XCTAssertEqual(providerCalls, 0, "An unloaded screen must not mint an identity")
        mount(screen.controller)
        screen.controller.loadViewIfNeeded()

        try assertDisplayedCopyAndShare(screen, code: "ABCD23")
        try button("referral.button.copy", in: screen.controller).sendActions(for: .touchUpInside)

        XCTAssertEqual(screen.pasteboard.string, "ABCD23")
        XCTAssertEqual(providerCalls, 1, "Label, copy and share must use one controller snapshot")
        let after = UserDefaults.standard.persistentDomain(forName: appDomain) ?? [:]
        XCTAssertEqual(changedKeys(before: before, after: after), [],
                       "An injected identity must not initialize or mutate the shared store")
    }

    func testControllersOwnSeparateCodeSnapshots() throws {
        var firstCalls = 0
        var secondCalls = 0
        let first = makeScreen { firstCalls += 1; return "ABCD23" }
        let second = makeScreen { secondCalls += 1; return "XYZ789" }
        XCTAssertEqual(firstCalls, 0)
        XCTAssertEqual(secondCalls, 0)

        mount(first.controller)
        mount(second.controller)

        XCTAssertTrue(labels(in: first.controller.view).contains("ABCD23"))
        XCTAssertFalse(labels(in: first.controller.view).contains("XYZ789"))
        XCTAssertTrue(labels(in: second.controller.view).contains("XYZ789"))
        XCTAssertFalse(labels(in: second.controller.view).contains("ABCD23"))
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 1)
    }

    func testPersistedServiceCodeReopensWithoutChangingReferralOrMoneyState() throws {
        let store = try makeStore(code: "JKLM23")
        let before = store.domain
        let first = makeScreen { store.service.getMyCode() }
        mount(first.controller)
        try assertDisplayedCopyAndShare(first, code: "JKLM23")

        let reopened = ReferralService(
            defaults: store.defaults,
            balanceService: makeWallet(defaults: store.defaults)
        )
        let second = makeScreen { reopened.getMyCode() }
        mount(second.controller)
        XCTAssertTrue(labels(in: second.controller.view).contains("JKLM23"))
        try button("referral.button.copy", in: second.controller).sendActions(for: .touchUpInside)
        XCTAssertEqual(second.pasteboard.string, "JKLM23")
        XCTAssertEqual(store.domain as NSDictionary, before as NSDictionary)
    }

    func testFreshServicePersistsOnlyItsOwnCodeAndRetainsItOnReopen() throws {
        let store = try makeStore()
        let before = store.domain
        let screen = makeScreen { store.service.getMyCode() }
        XCTAssertNil(store.defaults.string(forKey: "referral_my_code"))
        mount(screen.controller)
        let stored = try XCTUnwrap(store.defaults.string(forKey: "referral_my_code"))

        XCTAssertEqual(stored.count, 6)
        XCTAssertTrue(stored.allSatisfy { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) })
        try assertDisplayedCopyAndShare(screen, code: stored)

        let reopened = ReferralService(
            defaults: store.defaults,
            balanceService: makeWallet(defaults: store.defaults)
        )
        let second = makeScreen { reopened.getMyCode() }
        mount(second.controller)
        XCTAssertTrue(labels(in: second.controller.view).contains(stored))
        var after = store.domain
        after.removeValue(forKey: "referral_my_code")
        XCTAssertEqual(after as NSDictionary, before as NSDictionary,
                       "Reading/copying/sharing must not apply a code or mutate money")
    }

    private func makeScreen(provider: @escaping () -> String) -> Screen {
        let pasteboard = UIPasteboard.withUniqueName()
        pasteboardNames.append(pasteboard.name)
        let share = ReferralPersonalCodeShareCapture()
        let controller = ReferralViewController(
            personalCodeProvider: provider,
            pasteboard: pasteboard,
            activityControllerFactory: { share.makeController(items: $0) }
        )
        return Screen(controller: controller, pasteboard: pasteboard, share: share)
    }

    private func mount(_ controller: UIViewController) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        windows.append(window)
        window.isHidden = false
        controller.loadViewIfNeeded()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
    }

    private func assertDisplayedCopyAndShare(_ screen: Screen, code: String) throws {
        XCTAssertTrue(labels(in: screen.controller.view).contains(code))
        XCTAssertFalse(labels(in: screen.controller.view).contains("WAKEUP-7K2"))
        try button("referral.button.copy", in: screen.controller).sendActions(for: .touchUpInside)
        XCTAssertEqual(screen.pasteboard.string, code)
        try button("referral.button.share", in: screen.controller).sendActions(for: .touchUpInside)
        XCTAssertEqual(screen.share.items.count, 1)
        let items = try XCTUnwrap(screen.share.items.first)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first as? String,
                       Localized.format("referral.share.message", code, MoneyFormatter.string(200)))
        let activity = try XCTUnwrap(screen.share.controller)
        if let popover = activity.popoverPresentationController {
            XCTAssertTrue(popover.sourceView === screen.controller.view)
            XCTAssertEqual(popover.sourceRect, screen.controller.view.bounds)
        }
    }

    private func button(_ key: String, in controller: UIViewController) throws -> SPButton {
        try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? SPButton }
            .first { $0.accessibilityLabel == Localized.text(key) })
    }

    private func labels(in view: UIView) -> [String] {
        descendants(of: view).compactMap { ($0 as? UILabel)?.text }
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func makeStore(code: String? = nil) throws -> Store {
        let name = "test.referral.personal-code.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(750.0, forKey: "user_balance")
        defaults.set("XYZ789", forKey: "referral_applied_code")
        if let code { defaults.set(code, forKey: "referral_my_code") }
        let service = ReferralService(defaults: defaults, balanceService: makeWallet(defaults: defaults))
        let store = Store(name: name, defaults: defaults, service: service)
        stores.append(store)
        return store
    }

    private func makeWallet(defaults: UserDefaults) -> BalanceService {
        let repository = TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults))
        return BalanceService(defaults: defaults, transactionRepository: repository,
                              notificationCenter: NotificationCenter())
    }

    /// Report key names only; shared-domain values are never written, restored or logged.
    private func changedKeys(before: [String: Any], after: [String: Any]) -> [String] {
        Set(before.keys).union(after.keys).filter { key in
            guard let lhs = before[key], let rhs = after[key] else { return true }
            return !NSDictionary(dictionary: ["value": lhs]).isEqual(NSDictionary(dictionary: ["value": rhs]))
        }.sorted()
    }
}

@MainActor
private final class ReferralPersonalCodeShareCapture {
    private(set) var items: [[Any]] = []
    private(set) var controller: UIActivityViewController?

    func makeController(items: [Any]) -> UIActivityViewController {
        self.items.append(items)
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        self.controller = controller
        return controller
    }
}
