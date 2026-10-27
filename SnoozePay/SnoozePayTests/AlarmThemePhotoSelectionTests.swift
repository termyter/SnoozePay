import PhotosUI
import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmThemePhotoSelectionTests: XCTestCase {
    func testLatestPhotoWinsWhenEarlierLoadFinishesFirst() {
        assertLatestPhotoWins(completionOrder: [0, 1])
    }

    func testLatestPhotoWinsWhenEarlierLoadFinishesLast() {
        assertLatestPhotoWins(completionOrder: [1, 0])
    }

    func testOpeningAnotherPhotosRequestInvalidatesLoadBeforeItsResultArrives() throws {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        try harness.tapTile(6)
        XCTAssertEqual(harness.presentedPickers.count, 1)

        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 0)
        XCTAssertNil(harness.controller.presentedViewController)
    }

    func testPresetInvalidatesAnAlreadyQueuedPhotoCompletion() throws {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.finish(0, with: harness.firstImage)
        try harness.tapTile(1)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [.ocean])
        XCTAssertEqual(harness.navigation.popCalls, 1)
        XCTAssertTrue(harness.navigation.topViewController === harness.root)
    }

    func testPhotosCancellationInvalidatesPendingLoadWithoutChangingTheme() {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.controller.picker(PHPickerViewController(configuration: PHPickerConfiguration()), didFinishPicking: [])
        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 0)
        XCTAssertTrue(harness.navigation.topViewController === harness.controller)
    }

    func testDoneInvalidatesAnAlreadyQueuedPhotoCompletion() throws {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.finish(0, with: harness.firstImage)
        let barView = try XCTUnwrap(harness.controller.navigationItem.rightBarButtonItem?.customView)
        let done = try XCTUnwrap(descendants(of: barView).compactMap { $0 as? SPButton }.first)
        done.sendActions(for: .touchUpInside)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 1)
        XCTAssertTrue(harness.navigation.topViewController === harness.root)
    }

    func testBackNavigationInvalidatesAnAlreadyQueuedPhotoCompletion() {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.finish(0, with: harness.firstImage)
        harness.navigation.popViewController(animated: false)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 1)
        XCTAssertTrue(harness.navigation.topViewController === harness.root)
        harness.startPhoto(harness.secondImage)
        XCTAssertEqual(harness.completions.count, 1, "A departed picker must not start another load")
    }

    func testAnotherNavigationOwnerRejectsTheQueuedPhotoWithoutPoppingThatScreen() {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.finish(0, with: harness.firstImage)
        let foreign = UIViewController()
        harness.navigation.pushViewController(foreign, animated: false)
        XCTAssertTrue(harness.navigation.topViewController === foreign)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 0)
        XCTAssertNil(harness.controller.presentedViewController)
        XCTAssertNil(foreign.presentedViewController)
        XCTAssertTrue(harness.navigation.topViewController === foreign)
        harness.navigation.popViewController(animated: false)
        let manualPopCalls = harness.navigation.popCalls
        XCTAssertEqual(manualPopCalls, 1)
        XCTAssertTrue(harness.navigation.topViewController === harness.controller)
        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, manualPopCalls)
        XCTAssertNil(harness.controller.presentedViewController)
        XCTAssertTrue(harness.navigation.topViewController === harness.controller)
        harness.navigation.pushViewController(foreign, animated: false)
        harness.startPhoto(harness.secondImage)
        XCTAssertEqual(harness.completions.count, 1, "Only the navigation owner may start a photo load")
    }

    func testFirstPhotoCompletionAfterNavigationReturnsCannotReviveTheDepartedRequest() throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive },
            "Navigation lifecycle requires the test host's active scene"
        )
        let harness = makeHarness(scene: scene)
        defer {
            harness.navigation.onDidShow = nil
            harness.close()
        }
        XCTAssertTrue(harness.controller.view.window === harness.window)
        XCTAssertTrue(harness.window.windowScene === scene)
        XCTAssertEqual(scene.activationState, .foregroundActive)
        XCTAssertTrue(harness.window.isKeyWindow)
        XCTAssertFalse(harness.window.isHidden)
        XCTAssertTrue(harness.navigation.viewIfLoaded?.window === harness.window)
        harness.startPhoto(harness.firstImage)
        harness.navigation.delegate = harness.navigation
        XCTAssertTrue(harness.navigation.delegate === harness.navigation)
        harness.traceNavigation("before-push")
        let foreign = UIViewController()
        let foreignShown = expectation(description: "foreign navigation owner shown")
        harness.navigation.onDidShow = { shown in
            if shown === foreign { foreignShown.fulfill() }
        }
        harness.navigation.pushViewController(foreign, animated: false)
        wait(for: [foreignShown], timeout: 5)
        harness.traceNavigation("after-push-wait")
        XCTAssertTrue(harness.navigation.topViewController === foreign)

        let pickerShown = expectation(description: "theme picker shown again")
        harness.navigation.onDidShow = { [weak picker = harness.controller] shown in
            if shown === picker { pickerShown.fulfill() }
        }
        harness.navigation.popViewController(animated: false)
        wait(for: [pickerShown], timeout: 5)
        harness.traceNavigation("after-return-wait")
        XCTAssertTrue(harness.navigation.topViewController === harness.controller)
        let manualPopCalls = harness.navigation.popCalls
        XCTAssertEqual(manualPopCalls, 1)
        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, manualPopCalls)
        XCTAssertNil(harness.controller.presentedViewController)
        XCTAssertTrue(harness.navigation.topViewController === harness.controller)
    }

    func testTemporaryPhotoPickerCoverDoesNotInvalidateTheCurrentLoad() {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.controller.viewWillDisappear(false)
        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertEqual(harness.selectedThemes, [.custom(imagePath: harness.firstURL)])
        XCTAssertEqual(harness.savedImages.count, 1)
        XCTAssertTrue(harness.savedImages.first === harness.firstImage)
        XCTAssertEqual(harness.navigation.popCalls, 1)
    }

    func testDismissingThePickerHostInvalidatesAnAlreadyQueuedPhotoCompletion() throws {
        let harness = makeHarness(modal: true)
        defer { harness.close() }
        let host = try XCTUnwrap(harness.navigation.presentingViewController)
        XCTAssertTrue(host === harness.window.rootViewController)
        harness.startPhoto(harness.firstImage)
        harness.finish(0, with: harness.firstImage)
        let dismissed = expectation(description: "picker host dismissed")
        harness.navigation.dismiss(animated: false) { dismissed.fulfill() }
        wait(for: [dismissed], timeout: 5)
        XCTAssertNil(harness.navigation.presentingViewController)
        XCTAssertNil(host.presentedViewController)
        XCTAssertTrue(harness.window.rootViewController === host)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 0)
        XCTAssertNil(harness.controller.presentedViewController)
    }

    func testUnsupportedProviderInvalidatesAnOlderLoadWithoutStartingAnother() {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.controller.loadSelectedPhoto(from: NSItemProvider())
        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertEqual(harness.completions.count, 1)
        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 0)
    }

    func testMissingLoadedImageKeepsPreviousThemeAndDoesNotSave() {
        assertInvalidLoadedObject(nil)
    }

    func testWrongLoadedObjectKeepsPreviousThemeAndDoesNotSave() {
        assertInvalidLoadedObject(NSString(string: "not an image"))
    }

    func testSaveFailureKeepsPreviousThemeAndShowsTheExistingError() {
        let harness = makeHarness()
        defer { harness.close() }
        harness.rejectFirstSave = true
        harness.startPhoto(harness.firstImage)
        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertEqual(harness.savedImages.count, 1)
        XCTAssertTrue(harness.savedImages.first === harness.firstImage)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 0)
        let alert = harness.controller.presentedViewController as? UIAlertController
        XCTAssertEqual(alert?.title, Localized.text("create_alarm.theme_picker.error.title"))
        XCTAssertEqual(alert?.message, Localized.text("create_alarm.theme_picker.error.message"))
    }

    func testStaleWriteFailureCannotSaveOrShowAnErrorAfterTheLatestSelection() {
        let harness = makeHarness()
        defer { harness.close() }
        harness.rejectFirstSave = true
        harness.startPhoto(harness.firstImage)
        harness.startPhoto(harness.secondImage)
        harness.finish(1, with: harness.secondImage)
        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertEqual(harness.savedImages.count, 1)
        XCTAssertTrue(harness.savedImages.first === harness.secondImage)
        XCTAssertEqual(harness.selectedThemes, [.custom(imagePath: harness.secondURL)])
        XCTAssertEqual(harness.navigation.popCalls, 1)
        XCTAssertNil(harness.controller.presentedViewController)
    }

    func testDuplicateLatestCompletionSavesSelectsAndNavigatesOnlyOnce() {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.finish(0, with: harness.firstImage)
        harness.finish(0, with: harness.firstImage)
        runMainQueueTurn()

        XCTAssertEqual(harness.savedImages.count, 1)
        XCTAssertEqual(harness.selectedThemes, [.custom(imagePath: harness.firstURL)])
        XCTAssertEqual(harness.navigation.popCalls, 1)
    }

    private func assertLatestPhotoWins(completionOrder: [Int]) {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.startPhoto(harness.secondImage)
        let images = [harness.firstImage, harness.secondImage]
        for index in completionOrder { harness.finish(index, with: images[index]) }
        runMainQueueTurn()

        XCTAssertEqual(harness.savedImages.count, 1)
        XCTAssertTrue(harness.savedImages.first === harness.secondImage)
        XCTAssertEqual(harness.selectedThemes, [.custom(imagePath: harness.secondURL)])
        XCTAssertEqual(harness.navigation.popCalls, 1)
        XCTAssertTrue(harness.navigation.topViewController === harness.root)
    }

    private func assertInvalidLoadedObject(_ object: Any?) {
        let harness = makeHarness()
        defer { harness.close() }
        harness.startPhoto(harness.firstImage)
        harness.finish(0, with: object)
        runMainQueueTurn()

        XCTAssertTrue(harness.savedImages.isEmpty)
        XCTAssertEqual(harness.selectedThemes, [])
        XCTAssertEqual(harness.navigation.popCalls, 0)
        XCTAssertNil(harness.controller.presentedViewController)
    }

    private func makeHarness(modal: Bool = false, scene: UIWindowScene? = nil) -> PhotoSelectionHarness {
        let harness = PhotoSelectionHarness()
        harness.mount(modal: modal, scene: scene)
        return harness
    }

    private func runMainQueueTurn() {
        let turn = expectation(description: "queued photo completion handled")
        DispatchQueue.main.async { turn.fulfill() }
        wait(for: [turn], timeout: 5)
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}

@MainActor
private final class PhotoSelectionHarness {
    let firstImage = UIImage()
    let secondImage = UIImage()
    let firstURL = URL(fileURLWithPath: "/unused/theme-first.jpg")
    let secondURL = URL(fileURLWithPath: "/unused/theme-second.jpg")
    let root = UIViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    var completions: [(Any?) -> Void] = []
    var savedImages: [UIImage] = []
    var selectedThemes: [AlarmTheme] = []
    var presentedPickers: [PHPickerViewController] = []
    var rejectFirstSave = false
    private weak var previousKeyWindow: UIWindow?
    private var usesVisibleScene = false

    lazy var navigation = PhotoSelectionNavigationController(rootViewController: root)
    lazy var controller = AlarmThemePickerViewController(
        currentTheme: .forest,
        onSelect: { [weak self] in self?.selectedThemes.append($0) },
        loadPhoto: { [weak self] _, completion in self?.completions.append(completion) },
        saveImage: { [weak self] image in
            guard let self else { return nil }
            self.savedImages.append(image)
            if image === self.firstImage { return self.rejectFirstSave ? nil : self.firstURL }
            return self.secondURL
        },
        presentPhotoPicker: { [weak self] in self?.presentedPickers.append($0) }
    )

    func mount(modal: Bool, scene: UIWindowScene? = nil) {
        let appeared = scene.map { _ in XCTestExpectation(description: "visible navigation host appeared") }
        if let scene {
            previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            window.windowScene = scene
            window.frame = scene.coordinateSpace.bounds
            usesVisibleScene = true
            navigation.onTrace = { [weak self] in self?.traceNavigation($0) }
            navigation.onDidAppear = { appeared?.fulfill() }
        }
        navigation.setViewControllers([root, controller], animated: false)
        window.rootViewController = modal ? UIViewController() : navigation
        if usesVisibleScene { window.makeKeyAndVisible() } else { window.isHidden = false }
        window.layoutIfNeeded()
        if modal {
            guard let host = window.rootViewController else {
                return XCTFail("Modal harness requires a presenting host")
            }
            let presented = XCTestExpectation(description: "picker host presented")
            host.present(navigation, animated: false) { presented.fulfill() }
            XCTAssertEqual(XCTWaiter.wait(for: [presented], timeout: 5), .completed)
            XCTAssertTrue(host.presentedViewController === navigation)
            XCTAssertTrue(navigation.presentingViewController === host)
            XCTAssertTrue(navigation.topViewController === controller)
            XCTAssertTrue(controller.parent === navigation)
        }
        controller.loadViewIfNeeded()
        if let appeared {
            // UIKit must deliver the real appearance before a request exists.
            // Hierarchy attachment and modal completion alone did not prove it.
            XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 5), .completed)
            navigation.onDidAppear = nil
            traceNavigation("mounted")
        }
    }

    func close() {
        navigation.onDidAppear = nil
        window.isHidden = true
        window.rootViewController = nil
        if usesVisibleScene {
            window.windowScene = nil
            previousKeyWindow?.makeKeyAndVisible()
            previousKeyWindow = nil
            traceNavigation("closed")
            navigation.onTrace = nil
        }
    }

    func traceNavigation(_ phase: String) {
        guard usesVisibleScene else { return }
        // Only fixture identities/lifecycle state; no user or image contents.
        let activation = window.windowScene?.activationState.rawValue ?? -1
        let mounted = navigation.viewIfLoaded?.window === window
        let pickerOnTop = navigation.topViewController === controller
        let ownsDelegate = navigation.delegate === navigation
        let didShow = navigation.responds(to: #selector(
            UINavigationControllerDelegate.navigationController(_:didShow:animated:)
        ))
        print("PhotoNavigation \(ObjectIdentifier(navigation)) \(phase) scene=\(activation) "
              + "key=\(window.isKeyWindow) hidden=\(window.isHidden) mounted=\(mounted) "
              + "pickerTop=\(pickerOnTop) delegate=\(ownsDelegate) respondsDidShow=\(didShow) "
              + "transition=\(navigation.transitionCoordinator != nil)")
    }

    func startPhoto(_ image: UIImage) {
        controller.loadSelectedPhoto(from: NSItemProvider(object: image))
    }

    func finish(_ index: Int, with object: Any?) { completions[index](object) }

    func tapTile(_ item: Int) throws {
        let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        controller.collectionView(collection, didSelectItemAt: IndexPath(item: item, section: 0))
    }
}

@MainActor
private final class PhotoSelectionNavigationController: UINavigationController, UINavigationControllerDelegate {
    private(set) var popCalls = 0
    var onDidShow: ((UIViewController) -> Void)?
    var onDidAppear: (() -> Void)?
    var onTrace: ((String) -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onTrace?("viewDidAppear")
        onDidAppear?()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onTrace?("viewDidDisappear")
    }

    override func popViewController(animated: Bool) -> UIViewController? {
        popCalls += 1
        return super.popViewController(animated: false)
    }

    func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
        onTrace?("didShow:\(ObjectIdentifier(viewController))")
        onDidShow?(viewController)
    }

    func navigationController(
        _ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool
    ) {
        onTrace?("willShow:\(ObjectIdentifier(viewController))")
    }
}
