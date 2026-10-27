import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class WakeHistoryHostedLayoutTests: XCTestCase {
    private var fixtures: [WakeHistoryLayoutFixture] = []
    private let unreadable = "Не удалось прочитать историю подъёмов."
    private let calculation = "Не удалось рассчитать время подъёма по записанной истории."
    private let comparison = "Сравнение времени подъёма недоступно."

    override func tearDown() {
        for fixture in fixtures.reversed() {
            fixture.navigation?.onDidAppear = nil
            if let window = fixture.window {
                XCTAssertNil(fixture.controller.presentedViewController)
                XCTAssertNil(fixture.navigation?.presentedViewController)
                if let presented = fixture.navigation?.presentedViewController
                    ?? fixture.controller.presentedViewController {
                    let dismissed = expectation(description: "owned unexpected presentation dismissed")
                    presented.dismiss(animated: false) { dismissed.fulfill() }
                    XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
                    XCTAssertNil(fixture.controller.presentedViewController)
                    XCTAssertNil(fixture.navigation?.presentedViewController)
                }
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
                if let previous = fixture.previousKeyWindow, previous.windowScene === fixture.scene {
                    previous.makeKeyAndVisible()
                }
            }
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
        }
        fixtures.removeAll()
        super.tearDown()
    }

    func testHostedTimestampFailureReloadAndDefensiveCardStatesFitInBothThemes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let fixture = try makeFixture(style: style, unreadableDays: false)
            try assertTimeFailure(fixture, phase: "times-unreadable")
            try fixture.seedHealthyHistory()
            reload(fixture)
            try assertHealthyCard(fixture, phase: "healthy")
            fixture.defaults.set(Data("broken wake times".utf8), forKey: "wake_times")
            reload(fixture)
            try assertTimeFailure(fixture, phase: "times-unreadable-again")
            try exerciseDefensiveCardAPI(fixture)
            try fixture.seedHealthyHistory()
            reload(fixture)
            try assertHealthyCard(fixture, phase: "healthy-reload")
        }
    }

    func testHostedDayFailureWithholdsOverviewAndHealthyReloadRestoresVisibleStatistics() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let fixture = try makeFixture(style: style, unreadableDays: true)
            XCTAssertEqual(fixture.model.overviewUnavailableReason, .wakeHistoryUnreadable)
            XCTAssertTrue(fixture.controller.scrollView.isHidden)
            XCTAssertFalse(fixture.controller.emptyState.isHidden)
            XCTAssertEqual(fixture.model.streak, 0)
            XCTAssertTrue(fixture.model.weekMoneyDays.isEmpty)
            XCTAssertTrue(fixture.model.heatmapDays.isEmpty)
            XCTAssertNil(fixture.model.weekMoneySummary.saved)
            XCTAssertEqual(fixture.defaults.integer(forKey: "best_streak"), 100)
            XCTAssertFalse(visibleStrings(fixture.controller.emptyState)
                .contains(Localized.text("statistics.empty.body")))
            try assertLabel(unreadable, in: fixture.controller.emptyState,
                            fixture: fixture, phase: "days-unreadable")
            try fixture.seedHealthyHistory()
            reload(fixture)
            XCTAssertNil(fixture.model.overviewUnavailableReason)
            XCTAssertTrue(fixture.controller.emptyState.isHidden)
            XCTAssertFalse(fixture.model.weekMoneyDays.isEmpty)
            try assertHealthyCard(fixture, phase: "days-healthy-reload")
        }
    }

    private func makeFixture(style: UIUserInterfaceStyle, unreadableDays: Bool) throws -> WakeHistoryLayoutFixture {
        let fixture = try WakeHistoryLayoutFixture(style: style)
        fixtures.append(fixture)
        try fixture.seedHealthyHistory()
        fixture.defaults.set(Data("unreadable owned wake history".utf8),
                             forKey: unreadableDays ? "wake_days" : "wake_times")
        let prepared = fixture.domain
        try mount(fixture)
        XCTAssertEqual(fixture.domain, prepared, "Owned high best_streak makes this read-only load stable")
        return fixture
    }

    private func mount(_ fixture: WakeHistoryLayoutFixture) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "A real active scene is required; no fallback")
        fixture.scene = scene
        fixture.previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let bounds = scene.effectiveGeometry.coordinateSpace.bounds
        window.frame = CGRect(origin: bounds.origin,
                              size: CGSize(width: min(bounds.width, 390), height: bounds.height))
        let navigation = WakeHistoryLayoutNavigationController(rootViewController: fixture.controller)
        fixture.window = window
        fixture.navigation = navigation
        let appeared = expectation(description: "owned Statistics navigation really appeared")
        navigation.onDidAppear = { appeared.fulfill() }
        defer { navigation.onDidAppear = nil }
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        _ = try XCTUnwrap(XCTWaiter.wait(for: [appeared], timeout: 5) == .completed ? window : nil,
                          "Real UIKit appearance must complete within this fresh fixture's deadline")
        layout(fixture)
        try assertReady(fixture)
    }

    private func assertReady(_ fixture: WakeHistoryLayoutFixture) throws {
        let window = try XCTUnwrap(fixture.window)
        let scene = try XCTUnwrap(fixture.scene)
        let navigation = try XCTUnwrap(fixture.navigation)
        XCTAssertEqual(scene.activationState, .foregroundActive)
        XCTAssertTrue(window.windowScene === scene)
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertFalse(window.isHidden)
        XCTAssertTrue(window.rootViewController === navigation)
        XCTAssertGreaterThan(navigation.appearanceCount, 0)
        XCTAssertTrue(navigation.topViewController === fixture.controller)
        XCTAssertTrue(fixture.controller.parent === navigation)
        XCTAssertTrue(fixture.controller.viewIfLoaded?.window === window)
        XCTAssertTrue(navigation.viewIfLoaded?.window === window)
        XCTAssertEqual(fixture.controller.traitCollection.userInterfaceStyle, fixture.style)
        XCTAssertTrue(valid(window.bounds))
        XCTAssertTrue(valid(fixture.controller.view.bounds))
        let scale = window.screen.scale
        _ = try XCTUnwrap(scale.isFinite && scale > 0 ? window : nil, "Positive actual display scale required")
        let pixel = 1 / scale
        XCTAssertEqual(window.bounds.width, min(scene.effectiveGeometry.coordinateSpace.bounds.width, 390),
                       accuracy: pixel, "Qualify the actual compact width, not the requested value")
        XCTAssertGreaterThanOrEqual(window.bounds.width, 320)
        XCTAssertLessThanOrEqual(window.bounds.width, 390 + pixel)
        let ready = scene.activationState == .foregroundActive && window.isKeyWindow && !window.isHidden
            && window.windowScene === scene && navigation.appearanceCount > 0
            && fixture.controller.viewIfLoaded?.window === window && valid(window.bounds)
        _ = try XCTUnwrap(ready ? window : nil, "Do not count geometry from an unready host")
    }

    private func reload(_ fixture: WakeHistoryLayoutFixture) {
        let prepared = fixture.domain
        fixture.model.loadData()
        layout(fixture)
        XCTAssertEqual(fixture.domain, prepared, "Compare after fixture writes, not across an app write")
    }

    private func layout(_ fixture: WakeHistoryLayoutFixture) {
        fixture.window?.setNeedsLayout()
        fixture.controller.view.setNeedsLayout()
        fixture.window?.layoutIfNeeded()
        fixture.controller.view.layoutIfNeeded()
    }

    private func assertTimeFailure(_ fixture: WakeHistoryLayoutFixture, phase: String) throws {
        XCTAssertNil(fixture.model.overviewUnavailableReason)
        XCTAssertTrue(fixture.model.ledgerReadable)
        XCTAssertEqual(fixture.model.charges.count, 1)
        XCTAssertEqual(fixture.model.walletCurrency, .rub)
        XCTAssertFalse(fixture.model.weekMoneyDays.isEmpty)
        XCTAssertFalse(fixture.model.heatmapDays.isEmpty)
        XCTAssertEqual(fixture.model.wakeTimeAvailability, .unavailable(.historyUnreadable))
        XCTAssertFalse(fixture.controller.scrollView.isHidden)
        XCTAssertTrue(fixture.controller.emptyState.isHidden)
        XCTAssertFalse(fixture.controller.wakeTimeCard.isHidden)
        XCTAssertFalse(allStrings(fixture.controller.wakeTimeCard).contains("8:05"))
        try assertLabel(unreadable, in: fixture.controller.wakeTimeCard, fixture: fixture, phase: phase)
    }

    private func assertHealthyCard(_ fixture: WakeHistoryLayoutFixture, phase: String) throws {
        XCTAssertFalse(fixture.controller.scrollView.isHidden)
        XCTAssertTrue(fixture.controller.emptyState.isHidden)
        XCTAssertFalse(fixture.controller.wakeTimeCard.isHidden)
        XCTAssertEqual(fixture.model.wakeTimeStats?.recentSampleCount, 5)
        XCTAssertEqual(fixture.model.wakeTimeStats?.medianMinutes, 485)
        XCTAssertFalse(allStrings(fixture.controller.wakeTimeCard).contains(unreadable))
        XCTAssertFalse(allStrings(fixture.controller.wakeTimeCard).contains(calculation))
        XCTAssertFalse(allStrings(fixture.controller.wakeTimeCard).contains(comparison))
        try assertLabel("8:05", in: fixture.controller.wakeTimeCard, fixture: fixture, phase: phase)
    }

    /// The issue's defensive component API, not a claim that valid Date aggregation emits 1440.
    private func exerciseDefensiveCardAPI(_ fixture: WakeHistoryLayoutFixture) throws {
        let prepared = fixture.domain
        let card = fixture.controller.wakeTimeCard
        card.apply(StatisticsViewModel.WakeTimeStats(
            medianMinutes: 1440, baselineMedianMinutes: nil, recentSampleCount: 5, minimumSamples: 5
        ))
        layout(fixture)
        try assertLabel(calculation, in: card, fixture: fixture, phase: "refused-median", requiresWrap: true)
        XCTAssertFalse(allStrings(card).contains("23:59"))
        XCTAssertFalse(allStrings(card).contains("8:05"))
        XCTAssertFalse(allStrings(card).contains(StatisticsViewModel.wakeSamplesPendingText(0)))
        card.apply(StatisticsViewModel.WakeTimeStats(
            medianMinutes: 485, baselineMedianMinutes: 1440, recentSampleCount: 5, minimumSamples: 5
        ))
        layout(fixture)
        try assertLabel(comparison, in: card, fixture: fixture, phase: "refused-baseline")
        try assertLabel("8:05", in: card, fixture: fixture, phase: "refused-baseline-clock")
        XCTAssertFalse(allStrings(card).contains("23:59"))
        XCTAssertFalse(allStrings(card).contains(calculation))
        XCTAssertEqual(fixture.domain, prepared)
    }

    private func assertLabel(
        _ text: String, in scope: UIView, fixture: WakeHistoryLayoutFixture,
        phase: String, requiresWrap: Bool = false
    ) throws {
        try assertReady(fixture)
        let matches = labels(scope).filter { ($0.attributedText?.string ?? $0.text) == text }
        XCTAssertEqual(matches.count, 1, "\(phase): require one actual exact-copy label")
        let label = try XCTUnwrap(matches.first, "\(phase): missing \(text)")
        let window = try XCTUnwrap(fixture.window)
        try reveal(label, fixture: fixture)
        layout(fixture)
        let font = try XCTUnwrap(label.font)
        let attributed = label.attributedText ?? NSAttributedString(string: text, attributes: [.font: font])
        let fullText = NSMutableAttributedString(attributedString: attributed)
        let range = NSRange(location: 0, length: fullText.length)
        let paragraph = (fullText.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        fullText.addAttribute(.paragraphStyle, value: paragraph, range: range)
        let natural = fullText.boundingRect(
            with: CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        let scale = window.screen.scale
        XCTAssertGreaterThan(scale, 0)
        XCTAssertTrue(scale.isFinite)
        _ = try XCTUnwrap(scale.isFinite && scale > 0 ? window : nil, "The actual screen scale must be valid")
        let tolerance = 1 / scale
        let requiredHeight = ceil(natural.height * scale) / scale
        let frame = label.convert(label.bounds, to: window)
        let textRect = label.textRect(forBounds: label.bounds, limitedToNumberOfLines: label.numberOfLines)
        let windowSafe = window.safeAreaLayoutGuide.layoutFrame.insetBy(dx: -tolerance, dy: -tolerance)
        let controllerSafe = fixture.controller.view.convert(
            fixture.controller.view.safeAreaLayoutGuide.layoutFrame, to: window
        ).insetBy(dx: -tolerance, dy: -tolerance)
        let scopeFrame = scope.convert(scope.bounds, to: window).insetBy(dx: -tolerance, dy: -tolerance)
        let visibility = ancestorVisibility(label, frame: frame, window: window, tolerance: tolerance)
            && windowSafe.contains(frame) && controllerSafe.contains(frame) && scopeFrame.contains(frame)
            && clearOfBars(frame, fixture: fixture, window: window)
        let scroll = fixture.controller.scrollView
        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
        let line = "WakeHistoryHostedLayout style=\(fixture.style.rawValue) phase=\(phase)"
            + " key=\(window.isKeyWindow) active=\(fixture.scene?.activationState == .foregroundActive)"
            + " window=\(window.bounds) label=\(frame) bounds=\(label.bounds)"
            + " safe=\(controllerSafe) windowSafe=\(windowSafe) offset=\(fixture.controller.scrollView.contentOffset)"
            + " viewport=\(viewport) insets=\(scroll.adjustedContentInset) scope=\(scopeFrame)"
            + " textRect=\(textRect) actualStyle=\(label.traitCollection.userInterfaceStyle.rawValue)"
            + " naturalHeight=\(natural.height) requiredHeight=\(requiredHeight) pixel=\(tolerance)"
            + " scale=\(scale) visible=\(visibility)"
            + " text=\(text)"
        let attachment = XCTAttachment(string: line)
        attachment.name = "Wake history \(fixture.style.rawValue) \(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(line)
        XCTAssertTrue(label.isDescendant(of: fixture.controller.view))
        XCTAssertTrue(valid(label.bounds), phase)
        XCTAssertTrue(valid(frame), phase)
        XCTAssertTrue(valid(textRect), phase)
        XCTAssertEqual(label.traitCollection.userInterfaceStyle, fixture.style)
        XCTAssertEqual(scope.traitCollection.userInterfaceStyle, fixture.style)
        XCTAssertTrue(visibility, "\(phase): actual label must fit every clipping viewport with visible ancestors")
        XCTAssertGreaterThan(label.textColor.resolvedColor(with: label.traitCollection).cgColor.alpha, 0)
        XCTAssertGreaterThan(natural.height, 0)
        XCTAssertTrue(natural.height.isFinite)
        XCTAssertGreaterThanOrEqual(label.bounds.height + tolerance, requiredHeight,
                                    "\(phase): full uncapped word-wrapped text must fit")
        if text != "8:05" { XCTAssertEqual(label.numberOfLines, 0) }
        if requiresWrap {
            XCTAssertGreaterThan(natural.height, font.lineHeight + tolerance,
                                 "The compact fixture must genuinely exercise multiline copy")
            XCTAssertGreaterThan(textRect.height, font.lineHeight + tolerance,
                                 "The actual uncapped UILabel text layout must use multiple lines")
        }
    }

    private func reveal(_ label: UILabel, fixture: WakeHistoryLayoutFixture) throws {
        let scroll = fixture.controller.scrollView
        guard label.isDescendant(of: scroll) else { return }
        let window = try XCTUnwrap(fixture.window)
        let safe = fixture.controller.view.safeAreaLayoutGuide.layoutFrame
        let viewport = scroll.bounds.inset(by: scroll.adjustedContentInset)
            .intersection(fixture.controller.view.convert(safe, to: scroll))
            .intersection(window.convert(window.safeAreaLayoutGuide.layoutFrame, to: scroll))
        _ = try XCTUnwrap(valid(viewport) ? scroll : nil, "A real usable scroll viewport is required")
        let rect = label.convert(label.bounds, to: scroll)
        let target = scroll.contentOffset.y + rect.midY - viewport.midY
        let minimum = -scroll.adjustedContentInset.top
        let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height
            + scroll.adjustedContentInset.bottom)
        let offset = CGPoint(x: scroll.contentOffset.x, y: min(maximum, max(minimum, target)))
        scroll.setContentOffset(offset, animated: false)
    }

    private func clearOfBars(_ frame: CGRect, fixture: WakeHistoryLayoutFixture, window: UIWindow) -> Bool {
        guard let navigation = fixture.navigation else { return false }
        let navigationBar: UIView = navigation.navigationBar
        if !navigationBar.isHidden && navigationBar.alpha > 0
            && navigationBar.convert(navigationBar.bounds, to: window).intersects(frame) {
            return false
        }
        if let toolbar = navigation.toolbar, !toolbar.isHidden && toolbar.alpha > 0
            && toolbar.convert(toolbar.bounds, to: window).intersects(frame) {
            return false
        }
        return true
    }

    private func ancestorVisibility(_ label: UILabel, frame: CGRect, window: UIWindow, tolerance: CGFloat) -> Bool {
        var view: UIView? = label
        var reachedWindow = false
        while let ancestor = view {
            guard !ancestor.isHidden, ancestor.alpha > 0, valid(ancestor.bounds) else { return false }
            if ancestor.clipsToBounds || ancestor.layer.masksToBounds || ancestor === window {
                let clip = ancestor.convert(ancestor.bounds, to: window).insetBy(dx: -tolerance, dy: -tolerance)
                guard valid(clip), clip.contains(frame) else { return false }
            }
            if let scroll = ancestor as? UIScrollView {
                let viewport = scroll.bounds.inset(by: scroll.adjustedContentInset)
                let clip = scroll.convert(viewport, to: window).insetBy(dx: -tolerance, dy: -tolerance)
                guard valid(clip), clip.contains(frame) else { return false }
            }
            if ancestor === window { reachedWindow = true; break }
            view = ancestor.superview
        }
        return reachedWindow
    }

    private func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite }
            && rect.width > 0 && rect.height > 0 && !rect.isNull
    }

    private func labels(_ view: UIView) -> [UILabel] {
        let own = (view as? UILabel).map { [$0] } ?? []
        return own + view.subviews.flatMap { labels($0) }
    }

    private func allStrings(_ view: UIView) -> [String] {
        labels(view).compactMap { $0.attributedText?.string ?? $0.text }
    }

    private func visibleStrings(_ view: UIView) -> [String] {
        guard !view.isHidden, view.alpha > 0 else { return [] }
        let own = (view as? UILabel).flatMap { $0.attributedText?.string ?? $0.text }
        return (own.map { [$0] } ?? []) + view.subviews.flatMap { visibleStrings($0) }
    }
}

@MainActor
private final class WakeHistoryLayoutFixture {
    let suite: String
    let defaults: UserDefaults
    let calendar: Calendar
    let now: Date
    let wakeStore: WakeEventStore
    let model: StatisticsViewModel
    let controller: StatisticsViewController
    let style: UIUserInterfaceStyle
    var window: UIWindow?
    var scene: UIWindowScene?
    var navigation: WakeHistoryLayoutNavigationController?
    weak var previousKeyWindow: UIWindow?

    init(style: UIUserInterfaceStyle) throws {
        let name = "test.wakeHistoryHosted.\(UUID().uuidString)"
        let ownedDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let ownedCalendar = StatisticsViewModel.mondayFirstCalendar
        let instant = Date()
        ownedDefaults.set(100, forKey: "best_streak")
        ownedDefaults.set(500.0, forKey: "user_balance")
        XCTAssertEqual(WalletCurrencyStore(defaults: ownedDefaults).freeze(.rub), .frozen(.rub))
        let wakes = WakeEventStore(defaults: ownedDefaults)
        let repository = TransactionRepository(defaults: ownedDefaults, wakeStore: wakes)
        XCTAssertTrue(repository.record(Transaction(type: .charge, amount: 50, currency: .rub, createdAt: instant)))
        let alarms = AlarmRepository(defaults: ownedDefaults, scheduler: WakeHistoryLayoutNoopScheduler())
        XCTAssertTrue(alarms.save(Alarm(penaltyAmount: 50)))
        let viewModel = StatisticsViewModel(repository: repository, wakeStore: wakes,
                                            alarmRepository: alarms, defaults: ownedDefaults, calendar: ownedCalendar)
        suite = name
        defaults = ownedDefaults
        calendar = ownedCalendar
        now = instant
        self.style = style
        wakeStore = wakes
        model = viewModel
        controller = StatisticsViewController(viewModel: viewModel)
        controller.overrideUserInterfaceStyle = style
        #if DEBUG
        XCTAssertFalse(controller.referralShortcutEnabled)
        controller.referralControllerFactory = {
            XCTFail("Hosted wake QA must not enter the held referral flow")
            return ReferralViewController(personalCodeProvider: { "HOSTQA" })
        }
        #endif
    }

    var domain: NSDictionary { NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]) }

    func seedHealthyHistory() throws {
        defaults.removeObject(forKey: "wake_days")
        defaults.removeObject(forKey: "wake_times")
        for offset in 1...5 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: now))
            let time = try XCTUnwrap(calendar.date(bySettingHour: 8, minute: 5, second: 0, of: day))
            wakeStore.recordWake(on: time, calendar: calendar)
        }
    }
}

@MainActor
private final class WakeHistoryLayoutNavigationController: UINavigationController {
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

@MainActor
private final class WakeHistoryLayoutNoopScheduler: AlarmScheduling {
    func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
        completion?(.success(()))
    }
    func cancel(_ alarmID: UUID) {}
}
