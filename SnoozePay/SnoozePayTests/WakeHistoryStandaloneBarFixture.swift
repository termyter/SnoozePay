import UIKit
import XCTest

/// Test-only state. Initial construction allocates no UIKit objects.
@MainActor
final class WakeStandaloneBarFixture {
    var scene: UIWindowScene?
    weak var previousKeyWindow: UIWindow?
    var window: UIWindow?
    var host: WakeStandaloneBarHostController?
    var navigationBar: UINavigationBar?
    var toolbar: UIToolbar?
    var navigationItem: UINavigationItem?
    var toolbarItem: UIBarButtonItem?

    func mount(in testCase: XCTestCase) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "A real active scene is required; no fallback")
        self.scene = scene
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        self.window = window
        let bounds = scene.effectiveGeometry.coordinateSpace.bounds
        window.frame = CGRect(origin: bounds.origin,
                              size: CGSize(width: min(bounds.width, 390), height: bounds.height))
        let host = WakeStandaloneBarHostController()
        self.host = host
        host.overrideUserInterfaceStyle = .light
        let navigationBar = UINavigationBar()
        let toolbar = UIToolbar()
        self.navigationBar = navigationBar
        self.toolbar = toolbar
        let navigationItem = UINavigationItem(title: "Owned navigation QA")
        let toolbarItem = UIBarButtonItem(title: "Owned toolbar QA", style: .plain, target: nil, action: nil)
        self.navigationItem = navigationItem
        self.toolbarItem = toolbarItem
        navigationBar.setItems([navigationItem], animated: false)
        toolbar.setItems([toolbarItem], animated: false)
        navigationBar.isHidden = true
        toolbar.isHidden = true
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(navigationBar)
        host.view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            navigationBar.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            navigationBar.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let appeared = testCase.expectation(description: "owned standalone public bar host really appeared")
        host.onDidAppear = { appeared.fulfill() }
        defer { host.onDidAppear = nil }
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        _ = try XCTUnwrap(XCTWaiter.wait(for: [appeared], timeout: 5) == .completed ? window : nil,
                          "Real UIKit appearance must complete within this fresh fixture's deadline")
        layout()
        try assertReady()
    }

    func layout() {
        window?.setNeedsLayout()
        host?.viewIfLoaded?.setNeedsLayout()
        window?.layoutIfNeeded()
        host?.viewIfLoaded?.layoutIfNeeded()
    }

    func assertReady() throws {
        let window = try XCTUnwrap(window)
        let scene = try XCTUnwrap(scene)
        let host = try XCTUnwrap(host)
        let rootView = try XCTUnwrap(host.viewIfLoaded)
        let navigationBar = try XCTUnwrap(navigationBar)
        let toolbar = try XCTUnwrap(toolbar)
        XCTAssertEqual(scene.activationState, .foregroundActive)
        XCTAssertTrue(window.windowScene === scene)
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertFalse(window.isHidden)
        XCTAssertTrue(window.rootViewController === host)
        XCTAssertGreaterThan(host.appearanceCount, 0)
        XCTAssertNil(host.parent)
        XCTAssertNil(host.navigationController)
        XCTAssertTrue(rootView.window === window)
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, .light)
        XCTAssertTrue(valid(window.bounds))
        XCTAssertTrue(valid(rootView.bounds))
        for bar in [navigationBar as UIView, toolbar as UIView] {
            XCTAssertTrue(bar.window === window)
            XCTAssertTrue(bar.isDescendant(of: rootView))
            XCTAssertEqual(bar.traitCollection.userInterfaceStyle, .light)
            XCTAssertTrue(valid(bar.bounds), "Intrinsic public bar geometry must be positive; no fallback")
            XCTAssertFalse(bar.hasAmbiguousLayout)
        }
        let scale = window.screen.scale
        _ = try XCTUnwrap(scale.isFinite && scale > 0 ? window : nil, "Positive actual display scale required")
        let pixel = 1 / scale
        XCTAssertEqual(window.bounds.width, min(scene.effectiveGeometry.coordinateSpace.bounds.width, 390),
                       accuracy: pixel)
        XCTAssertGreaterThanOrEqual(window.bounds.width, 320)
        XCTAssertLessThanOrEqual(window.bounds.width, 390 + pixel)
        let expectedNavigationItem = try XCTUnwrap(navigationItem)
        let expectedToolbarItem = try XCTUnwrap(toolbarItem)
        let actualNavigationItem = try XCTUnwrap(navigationBar.items?.first)
        let actualToolbarItem = try XCTUnwrap(toolbar.items?.first)
        XCTAssertEqual(navigationBar.items?.count, 1)
        XCTAssertEqual(toolbar.items?.count, 1)
        XCTAssertTrue(actualNavigationItem === expectedNavigationItem)
        XCTAssertTrue(actualToolbarItem === expectedToolbarItem)
        let ready = scene.activationState == .foregroundActive && window.isKeyWindow && !window.isHidden
            && window.windowScene === scene && window.rootViewController === host && host.appearanceCount > 0
            && rootView.window === window && valid(window.bounds) && valid(rootView.bounds)
        _ = try XCTUnwrap(ready ? window : nil, "Do not count geometry from an unready standalone host")
    }

    func close() {
        host?.onDidAppear = nil
        XCTAssertNil(host?.presentedViewController)
        if let presented = host?.presentedViewController { presented.dismiss(animated: false) }
        window?.isHidden = true
        window?.rootViewController = nil
        window?.windowScene = nil
        if let previousKeyWindow, previousKeyWindow.windowScene === scene { previousKeyWindow.makeKeyAndVisible() }
        window = nil
        host = nil
        navigationBar = nil
        toolbar = nil
        navigationItem = nil
        toolbarItem = nil
        previousKeyWindow = nil
        scene = nil
    }

    func basePayload(kind: String) -> [String: Any] {
        [
            "schema": 1, "nodeSchema": 2, "kind": kind, "hostKind": "PLAIN_OWNED_UIVIEWCONTROLLER",
            "style": UIUserInterfaceStyle.light.rawValue,
            "ownedWindowID": objectID(window), "windowBounds": nullable(window.map { rect($0.bounds) }),
            "key": nullable(window.map { $0.isKeyWindow }),
            "active": nullable(window.map { $0.windowScene?.activationState == .foregroundActive }),
            "windowHidden": nullable(window.map { $0.isHidden }),
            "sceneID": objectID(scene), "windowSceneID": objectID(window?.windowScene),
            "hostControllerID": objectID(host), "windowRootControllerID": objectID(window?.rootViewController),
            "hostViewID": objectID(host?.viewIfLoaded), "hostViewWindowID": objectID(host?.viewIfLoaded?.window),
            "hostParentID": objectID(host?.parent), "hostNavigationControllerID": objectID(host?.navigationController),
            "hostPresentedControllerID": objectID(host?.presentedViewController),
            "hostStyle": nullable(host.map { $0.traitCollection.userInterfaceStyle.rawValue }),
            "navigationBarStyle": nullable(navigationBar.map { $0.traitCollection.userInterfaceStyle.rawValue }),
            "toolbarStyle": nullable(toolbar.map { $0.traitCollection.userInterfaceStyle.rawValue }),
            "appearanceCount": nullable(host.map { $0.appearanceCount }),
            "ownNavigationBarID": objectID(navigationBar), "ownToolbarID": objectID(toolbar)
        ]
    }

    func contentPayload(for bar: UIView, role: String) -> [String: Any] {
        let actualIDs: [String]?
        let actualRole: String
        if let navigationBar = bar as? UINavigationBar {
            actualIDs = navigationBar.items?.map { objectID($0) }
            actualRole = "navigationBar"
        } else if let toolbar = bar as? UIToolbar {
            actualIDs = toolbar.items?.map { objectID($0) }
            actualRole = "toolbar"
        } else {
            actualIDs = nil
            actualRole = "OTHER_UIVIEW"
        }
        let isNavigation = role == "componentNavigationBar"
        let expectedBar: UIView? = isNavigation ? navigationBar : toolbar
        let expectedItem: AnyObject? = isNavigation ? navigationItem : toolbarItem
        return [
            "actualPublicRole": actualRole, "expectedOwnedBarID": objectID(expectedBar),
            "argumentIsExpectedBar": bar === expectedBar,
            "contentItemIDs": nullable(actualIDs), "contentItemCount": nullable(actualIDs?.count),
            "expectedContentItemID": objectID(expectedItem)
        ]
    }

    func objectID(_ object: AnyObject?) -> String {
        object.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
    }

    private func nullable(_ value: Any?) -> Any { value ?? NSNull() }

    private func rect(_ rect: CGRect) -> [String] {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].map { String(describing: $0) }
    }

    private func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite }
            && rect.width > 0 && rect.height > 0 && !rect.isNull
    }
}

/// Only observes real appearance; no custom bar or layout behavior.
@MainActor
final class WakeStandaloneBarHostController: UIViewController {
    var onDidAppear: (() -> Void)?
    private(set) var appearanceCount = 0

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appearanceCount += 1
        let completed = onDidAppear
        onDidAppear = nil
        completed?()
    }
}
