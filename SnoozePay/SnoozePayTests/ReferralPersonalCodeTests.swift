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

    private var hosts: [ReferralPersonalCodeHost] = []
    private var pasteboardNames: [UIPasteboard.Name] = []
    private var stores: [Store] = []

    override func tearDown() {
        for host in hosts.reversed() {
            host.navigation.onDidAppear = nil
            _ = dismissOwnedPresentation(in: host)
            host.window.isHidden = true
            host.window.rootViewController = nil
            host.window.windowScene = nil
            if let previous = host.previousKeyWindow, previous.windowScene === host.scene {
                previous.makeKeyAndVisible()
            }
        }
        hosts.removeAll()
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
        try mount(screen.controller)
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

        try mount(first.controller)
        try mount(second.controller)

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
        try mount(first.controller)
        try assertDisplayedCopyAndShare(first, code: "JKLM23")

        let reopened = ReferralService(
            defaults: store.defaults,
            balanceService: makeWallet(defaults: store.defaults)
        )
        let second = makeScreen { reopened.getMyCode() }
        try mount(second.controller)
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
        try mount(screen.controller)
        let stored = try XCTUnwrap(store.defaults.string(forKey: "referral_my_code"))

        XCTAssertEqual(stored.count, 6)
        XCTAssertTrue(stored.allSatisfy { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) })
        try assertDisplayedCopyAndShare(screen, code: stored)

        let reopened = ReferralService(
            defaults: store.defaults,
            balanceService: makeWallet(defaults: store.defaults)
        )
        let second = makeScreen { reopened.getMyCode() }
        try mount(second.controller)
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
            activityControllerFactory: { share.makeController(items: $0) },
            presentActivityController: { share.present(presenter: $0, activity: $1) }
        )
        return Screen(controller: controller, pasteboard: pasteboard, share: share)
    }

    private func mount(_ controller: UIViewController) throws {
        if let previous = hosts.last {
            _ = try XCTUnwrap(dismissOwnedPresentation(in: previous) ? previous : nil,
                              "The owned Share presentation must close before another host opens")
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "A real active test-host scene is required")
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let navigation = ReferralPersonalCodeNavigationController(rootViewController: controller)
        let host = ReferralPersonalCodeHost(window: window, scene: scene, navigation: navigation,
                                           previousKeyWindow: previousKeyWindow)
        hosts.append(host)
        let appeared = expectation(description: "real Referral navigation host appeared")
        navigation.onDidAppear = { appeared.fulfill() }
        defer { navigation.onDidAppear = nil }
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        _ = try XCTUnwrap(XCTWaiter.wait(for: [appeared], timeout: 5) == .completed ? host : nil,
                          "UIKit must deliver the owned navigation host's real viewDidAppear")
        controller.view.layoutIfNeeded()
        XCTAssertEqual(scene.activationState, .foregroundActive)
        XCTAssertTrue(window.windowScene === scene)
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertFalse(window.isHidden)
        XCTAssertGreaterThan(navigation.appearanceCount, 0)
        XCTAssertTrue(navigation.topViewController === controller)
        XCTAssertTrue(controller.parent === navigation)
        XCTAssertTrue(navigation.viewIfLoaded?.window === window)
        XCTAssertTrue(controller.viewIfLoaded?.window === window)
        let ready = scene.activationState == .foregroundActive && window.windowScene === scene
            && window.isKeyWindow && !window.isHidden && navigation.appearanceCount > 0
            && navigation.topViewController === controller && controller.parent === navigation
            && navigation.viewIfLoaded?.window === window && controller.viewIfLoaded?.window === window
        _ = try XCTUnwrap(ready ? host : nil, "Do not share from an unready scene/navigation hierarchy")
    }

    private func dismissOwnedPresentation(in host: ReferralPersonalCodeHost) -> Bool {
        guard let presented = host.navigation.presentedViewController
            ?? host.navigation.topViewController?.presentedViewController else { return true }
        let dismissed = expectation(description: "owned Share presentation dismissed")
        presented.dismiss(animated: false) { dismissed.fulfill() }
        let completed = XCTWaiter.wait(for: [dismissed], timeout: 5) == .completed
        XCTAssertTrue(completed, "UIKit must finish dismissing the owned presentation")
        let cleared = host.navigation.presentedViewController == nil
            && host.navigation.topViewController?.presentedViewController == nil
        XCTAssertTrue(cleared, "The old host must not retain a presented controller")
        return completed && cleared
    }

    private func assertDisplayedCopyAndShare(_ screen: Screen, code: String) throws {
        XCTAssertTrue(labels(in: screen.controller.view).contains(code))
        XCTAssertFalse(labels(in: screen.controller.view).contains("WAKEUP-7K2"))
        try button("referral.button.copy", in: screen.controller).sendActions(for: .touchUpInside)
        XCTAssertEqual(screen.pasteboard.string, code)
        let expectedView = try XCTUnwrap(screen.controller.viewIfLoaded)
        let expectedRect = expectedView.bounds
        let expectedWindow = try XCTUnwrap(expectedView.window)
        let expectedScene = try XCTUnwrap(expectedWindow.windowScene)
        XCTAssertFalse(expectedView === screen.share.wrongAnchor)
        XCTAssertNotEqual(expectedRect, screen.share.wrongRect)
        defer {
            if let host = hosts.last(where: { $0.navigation.topViewController === screen.controller }) {
                _ = dismissOwnedPresentation(in: host)
            }
            screen.share.wrongAnchor.removeFromSuperview()
        }
        try attachWrongAnchor(screen.share, to: expectedView)
        let presented = expectation(description: "real owned Share presentation completed")
        screen.share.onPresentationCompleted = { presented.fulfill() }
        defer { screen.share.onPresentationCompleted = nil }
        try button("referral.button.share", in: screen.controller).sendActions(for: .touchUpInside)
        XCTAssertEqual(screen.share.items.count, 1)
        let items = try XCTUnwrap(screen.share.items.first)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first as? String,
                       Localized.format("referral.share.message", code, MoneyFormatter.string(200)))
        let activity = try XCTUnwrap(screen.share.controller)
        XCTAssertTrue(screen.share.seededPopoverExists)
        XCTAssertTrue(screen.share.seededSourceView === screen.share.wrongAnchor)
        XCTAssertEqual(try XCTUnwrap(screen.share.seededSourceRect), screen.share.wrongRect)
        XCTAssertTrue(screen.share.seededSourceWasValid)
        XCTAssertTrue(screen.share.seededSourceSuperview === expectedView)
        XCTAssertTrue(screen.share.seededSourceWindow === expectedWindow)
        XCTAssertTrue(screen.share.seededSourceScene === expectedScene)
        XCTAssertEqual(screen.share.handoffCount, 1)
        XCTAssertTrue(screen.share.hadPopoverAtHandoff)
        XCTAssertTrue(try XCTUnwrap(screen.share.presenterAtHandoff) === screen.controller)
        XCTAssertTrue(try XCTUnwrap(screen.share.activityAtHandoff) === activity)
        XCTAssertTrue(try XCTUnwrap(screen.share.sourceViewAtHandoff) === expectedView)
        XCTAssertEqual(try XCTUnwrap(screen.share.sourceRectAtHandoff), expectedRect)
        XCTAssertEqual(try XCTUnwrap(screen.share.presenterBoundsAtHandoff), expectedRect)
        XCTAssertFalse(screen.share.sourceGetterWasNil)
        XCTAssertTrue(screen.share.sourceGetterMatchedPresenter)
        _ = try XCTUnwrap(XCTWaiter.wait(for: [presented], timeout: 5) == .completed ? activity : nil,
                          "Real Share presentation must finish before another host or teardown")
    }

    private func attachWrongAnchor(_ share: ReferralPersonalCodeShareCapture, to expectedView: UIView) throws {
        let window = try XCTUnwrap(expectedView.window)
        let scene = try XCTUnwrap(window.windowScene)
        let available = expectedView.safeAreaLayoutGuide.layoutFrame.intersection(expectedView.bounds)
        share.wrongAnchor.frame = CGRect(x: available.midX - 20, y: available.midY - 20, width: 40, height: 40)
        share.wrongAnchor.isHidden = false
        share.wrongAnchor.alpha = 1
        share.wrongAnchor.isUserInteractionEnabled = false
        expectedView.addSubview(share.wrongAnchor)
        XCTAssertTrue(share.wrongAnchor.superview === expectedView)
        XCTAssertTrue(share.wrongAnchor.window === window)
        XCTAssertTrue(share.wrongAnchor.window?.windowScene === scene)
        XCTAssertEqual(scene.activationState, .foregroundActive)
        XCTAssertTrue(available.contains(share.wrongAnchor.frame))
        XCTAssertTrue(window.bounds.contains(share.wrongAnchor.convert(share.wrongAnchor.bounds, to: window)))
        XCTAssertTrue(share.wrongAnchorIsReady)
        _ = try XCTUnwrap(share.wrongAnchorIsReady ? share.wrongAnchor : nil,
                          "The wrong-source control must be valid on-window before the factory sees it")
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
    let wrongAnchor = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let wrongRect = CGRect(x: 7, y: 11, width: 13, height: 17)
    private(set) var seededPopoverExists = false
    private(set) weak var seededSourceView: UIView?
    private(set) var seededSourceRect: CGRect?
    private(set) var seededSourceWasValid = false
    private(set) weak var seededSourceSuperview: UIView?
    private(set) weak var seededSourceWindow: UIWindow?
    private(set) weak var seededSourceScene: UIWindowScene?
    private var seededPopoverID: ObjectIdentifier?
    private(set) var handoffCount = 0
    private(set) var hadPopoverAtHandoff = false
    private(set) weak var presenterAtHandoff: UIViewController?
    private(set) weak var activityAtHandoff: UIActivityViewController?
    private(set) weak var sourceViewAtHandoff: UIView?
    private(set) var sourceRectAtHandoff: CGRect?
    private(set) var presenterBoundsAtHandoff: CGRect?
    private(set) var sourceGetterWasNil = true
    private(set) var sourceGetterMatchedPresenter = false
    var onPresentationCompleted: (() -> Void)?

    var wrongAnchorIsReady: Bool {
        guard let parent = wrongAnchor.superview, let window = wrongAnchor.window,
              window.windowScene?.activationState == .foregroundActive else { return false }
        var ancestor: UIView? = wrongAnchor
        while let view = ancestor {
            if view.isHidden || view.alpha <= 0 { return false }
            ancestor = view.superview
        }
        let frame = wrongAnchor.frame
        let components = [frame.minX, frame.minY, frame.width, frame.height,
                          wrongRect.minX, wrongRect.minY, wrongRect.width, wrongRect.height]
        return components.allSatisfy { $0.isFinite } && frame.size == CGSize(width: 40, height: 40)
            && !frame.isEmpty && parent.bounds.contains(frame) && !wrongRect.isEmpty
            && wrongAnchor.bounds.contains(wrongRect)
            && window.bounds.contains(wrongAnchor.convert(wrongAnchor.bounds, to: window))
    }

    func makeController(items: [Any]) -> UIActivityViewController {
        self.items.append(items)
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // A real popover makes the app's optional anchor branch mandatory on the phone runner.
        controller.modalPresentationStyle = .popover
        if let popover = controller.popoverPresentationController {
            seededSourceWasValid = wrongAnchorIsReady
            seededSourceSuperview = wrongAnchor.superview
            seededSourceWindow = wrongAnchor.window
            seededSourceScene = wrongAnchor.window?.windowScene
            popover.sourceView = wrongAnchor
            popover.sourceRect = wrongRect
            seededPopoverExists = true
            seededSourceView = popover.sourceView
            seededSourceRect = popover.sourceRect
            seededPopoverID = ObjectIdentifier(popover)
        }
        self.controller = controller
        return controller
    }

    /// Observe the actual app-owned handoff, then forward the original presentation unchanged.
    func present(presenter: UIViewController, activity: UIActivityViewController) {
        handoffCount += 1
        presenterAtHandoff = presenter
        activityAtHandoff = activity
        let popover = activity.popoverPresentationController
        let observedSource = popover?.sourceView
        let presenterView = presenter.viewIfLoaded
        let sourceItem = popover?.sourceItem.map { $0 as AnyObject }
        hadPopoverAtHandoff = popover != nil
        sourceViewAtHandoff = observedSource
        sourceRectAtHandoff = popover?.sourceRect
        presenterBoundsAtHandoff = presenterView?.bounds
        sourceGetterWasNil = observedSource == nil
        sourceGetterMatchedPresenter = observedSource != nil && presenterView != nil && observedSource === presenterView
        let sourceID = observedSource.map { ObjectIdentifier($0) }
        let weakAgrees = observedSource != nil && sourceViewAtHandoff != nil && observedSource === sourceViewAtHandoff
        let preTrace = "sourceNil=\(sourceGetterWasNil) sourceMatch=\(sourceGetterMatchedPresenter) "
            + "sourceID=\(String(describing: sourceID)) weakAgrees=\(weakAgrees) "
            + "source={\(describe(view: observedSource))} "
            + "presenter=\(describe(object: presenter)) presenterView={\(describe(view: presenterView))} "
            + "activity=\(describe(object: activity)) style=\(activity.modalPresentationStyle.rawValue) "
            + "seedPopover=\(String(describing: seededPopoverID)) "
            + "seedSourceValid=\(seededSourceWasValid) "
            + "handoffPopover=\(describe(object: popover)) sourceItem=\(describe(object: sourceItem)) "
            + "rect=\(String(describing: sourceRectAtHandoff)) bounds=\(String(describing: presenterBoundsAtHandoff))"

        presenter.present(activity, animated: true) { [weak self] in
            let completed = self?.onPresentationCompleted
            self?.onPresentationCompleted = nil
            completed?()
        }

        let postPopover = activity.popoverPresentationController
        let postSource = postPopover?.sourceView
        let postHandoffSource = sourceViewAtHandoff
        let postMatches = postHandoffSource != nil && postSource != nil && postHandoffSource === postSource
        print("ReferralShareHandoff count=\(handoffCount) prePopover=\(hadPopoverAtHandoff) pre={\(preTrace)} "
              + "postPopover=\(describe(object: postPopover)) postSource={\(describe(view: postSource))} "
              + "postMatchesHandoff=\(postMatches) "
              + "postRect=\(String(describing: postPopover?.sourceRect))")
    }

    private func describe(object: AnyObject?) -> String {
        object.map { "\(ObjectIdentifier($0)):\(String(describing: type(of: $0)))" } ?? "nil"
    }

    private func describe(view: UIView?) -> String {
        guard let view else { return "nil" }
        let window = view.window
        let scene = window?.windowScene
        let navigation = (presenterAtHandoff as? ReferralViewController)?.navigationController
        let ownsPresenter = navigation?.topViewController != nil && presenterAtHandoff != nil
            && navigation?.topViewController === presenterAtHandoff
        return "view=\(describe(object: view)) window=\(describe(object: window)) "
            + "scene=\(describe(object: scene)) active=\(scene?.activationState.rawValue ?? -1) "
            + "key=\(window?.isKeyWindow ?? false) hidden=\(window?.isHidden ?? true) "
            + "navOwnsPresenter=\(ownsPresenter) "
            + "appearances=\((navigation as? ReferralPersonalCodeNavigationController)?.appearanceCount ?? 0)"
    }
}

@MainActor
private final class ReferralPersonalCodeHost {
    let window: UIWindow
    let scene: UIWindowScene
    let navigation: ReferralPersonalCodeNavigationController
    weak var previousKeyWindow: UIWindow?

    init(window: UIWindow, scene: UIWindowScene, navigation: ReferralPersonalCodeNavigationController,
         previousKeyWindow: UIWindow?) {
        self.window = window
        self.scene = scene
        self.navigation = navigation
        self.previousKeyWindow = previousKeyWindow
    }
}

@MainActor
private final class ReferralPersonalCodeNavigationController: UINavigationController {
    private(set) var appearanceCount = 0
    var onDidAppear: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appearanceCount += 1
        let appeared = onDidAppear
        onDidAppear = nil
        appeared?()
    }
}
