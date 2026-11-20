import UIKit
import XCTest
@testable import SnoozePay

/// Dynamic Type, statistics slice 1: the page title and the cards that
/// `StatisticsViewController` builds itself — the hero «СЕРИЯ» with its
/// heatmap, «ПО ДНЯМ НЕДЕЛИ» and «ДИНАМИКА ОТКЛАДЫВАНИЙ» (#1111).
///
/// Same approach as `AlarmsListDynamicTypeTests`: every measurement sets the
/// category explicitly on the host window, so nothing depends on what the
/// simulator is set to. The screen runs on a pool suite with its own stores;
/// the date-dependent content (streak, heatmap month, trend) is replaced by a
/// fixed fixture after the load, so the geometry does not move with the calendar.
@MainActor
final class StatisticsDynamicTypeTests: XCTestCase {

    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
    private let narrow: CGFloat = 375
    /// Today's pinned trend card: the subtitle fits beside «Эта неделя».
    private static let shortSubtitle = StatisticsViewModel.subtitle(forDiff: 9)
    /// The card's longest string, which needs the headline column to wrap.
    private static let longSubtitle = StatisticsViewModel.subtitle(forDiff: 0)
    private let wide: CGFloat = 402

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Seam

    func testTheStatisticsRolesAreTheFixedFontsAtTheDefaultSizeAndCappedAtAX5() {
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        let grown = UITraitCollection(preferredContentSizeCategory: Self.ax5)
        let roles: [(UIFont, UIFont.TextStyle)] = [
            (AppTypography.moneyXl, .largeTitle), (AppTypography.h3, .title3), (AppTypography.moneyMd, .title3),
            (AppFonts.sans(.semibold, 10), .caption2), (AppFonts.sans(.bold, 12), .caption1),
            (AppFonts.sans(.medium, 11), .caption2), (AppFonts.sans(.semibold, 13), .footnote)
        ]
        for (fixed, style) in roles {
            let name = "\(fixed.fontName) \(fixed.pointSize)"
            let atLarge = AppTypography.scaled(fixed, as: style, compatibleWith: large)
            XCTAssertEqual(atLarge.pointSize, fixed.pointSize, "\(name) moved at the default size")
            XCTAssertEqual(atLarge.fontName, fixed.fontName, "\(name) changed face")
            let atAX5 = AppTypography.scaled(fixed, as: style, compatibleWith: grown).pointSize
            XCTAssertGreaterThan(atAX5, fixed.pointSize, "\(name) ignores Dynamic Type")
            XCTAssertLessThanOrEqual(atAX5, fixed.pointSize * AppTypography.maximumScale, "\(name) exceeded the cap")
        }
    }

    // MARK: - Default size

    /// Every frame measured on main (65cd789e; the tab is the same at
    /// d40b298a) with this harness and fixture, cold in a real window at
    /// `.large`, at both widths, with the subtitle that fits beside «Эта
    /// неделя». The long one is not pinned: main cuts «Эта неделя» beside it
    /// (`testBelowXLTheTrendSummaryKeepsItsRowAndItsCaptionWhole`).
    ///
    /// Six labels now get their width from a `.fill` stack instead of their
    /// own text (the meta lines must wrap at large sizes); their text is
    /// left-aligned and unchanged, so their origin and height are pinned and
    /// the text draws where it did.
    func testAtTheDefaultSizeTheTabIsUnchanged() throws {
        for width in [narrow, wide] {
            let screen = try hosted(.large, width: width, subtitle: Self.shortSubtitle)
            try assertTodaysGeometry(screen, width: width)
        }
    }

    // MARK: - Accessibility sizes

    func testAtAX5TheTextGrowsCappedAndTheChartsKeepTheirGeometry() throws {
        let regular = try hosted(.large, width: narrow)
        let grown = try hosted(Self.ax5, width: narrow)
        let texts = [
            Localized.text("statistics.title"), Localized.text("statistics.streak.caps"), "12", dayWord,
            lastSlip, Localized.text("statistics.streak.legend"), Localized.text("statistics.weekday.caps"),
            Localized.text("statistics.weekday.meta"), Localized.text("statistics.trend.caps"),
            Localized.text("statistics.trend.worse"), Localized.text("statistics.trend.no_change"),
            Localized.text("statistics.trend.week_caption"), Localized.text("statistics.trend.axis_start"),
            Localized.text("statistics.trend.axis_end"), "ПН"
        ]
        for text in texts {
            let before = try font(of: label(text, in: regular.view)).pointSize
            let after = try font(of: label(text, in: grown.view)).pointSize
            XCTAssertGreaterThan(after, before, "«\(text)» did not scale")
            XCTAssertLessThanOrEqual(after, before * AppTypography.maximumScale, "«\(text)» exceeded the cap")
        }
        // Searched inside the chart: «ЭТА НЕДЕЛЯ» above it has its own «Пн» (a later slice).
        for text in ["2,5", "Пн", "Ср"] {
            let before = try label(text, in: regular.controller.weekdayBarsView).font.pointSize
            let after = try label(text, in: grown.controller.weekdayBarsView).font.pointSize
            XCTAssertGreaterThan(after, before, "chart «\(text)» did not scale")
            XCTAssertLessThanOrEqual(after, before * AppTypography.maximumScale, "chart «\(text)» exceeded the cap")
        }
        XCTAssertGreaterThan(try font(of: grown.controller.weekdayHeadlineLabel).pointSize, AppTypography.h3.pointSize)
        // The cells and the bars keep their size; only the label rows grow.
        XCTAssertEqual(try firstHeatmapCell(in: grown).frame.size, CGSize(width: 39, height: 39))
        XCTAssertGreaterThan(try firstHeatmapCell(in: grown).frame.minY, 16 + 4, "the weekday header row did not grow")
        let bars = grown.controller.weekdayBarsView
        XCTAssertGreaterThan(bars.bounds.height, 132, "the value and caption rows did not grow")
        let tallest = try XCTUnwrap(bars.subviews.filter { !($0 is UILabel) }.map(\.frame.height).max())
        XCTAssertEqual(tallest, 92, accuracy: 0.01, "the bar area changed")
        XCTAssertEqual(grown.controller.trendBarsView.bounds.height, 100, accuracy: 0.01)
        // The streak count is drawn larger than today, not shrunk back to it.
        XCTAssertGreaterThan(try drawnPointSize(of: grown.controller.streakBigLabel), AppTypography.moneyXl.pointSize)
        try assertNothingClipped(in: grown)
    }

    /// XL–AX5 at both widths, with the longest real copy in the trend card and
    /// a four-digit streak: the «Эта неделя» column sits under the headline,
    /// nothing is clipped and no word is broken.
    func testFromXLTheTrendSummaryStacksAndNothingIsClipped() throws {
        let categories: [UIContentSizeCategory] = [.extraLarge, .extraExtraLarge, .extraExtraExtraLarge, Self.ax5]
        for category in categories {
            for width in [narrow, wide] {
                let screen = try hosted(category, width: width)
                let name = "\(category.rawValue) at \(width)"
                let caption = try label(Localized.text("statistics.trend.week_caption"), in: screen.view)
                let subtitle = screen.controller.trendSubtitleLabel
                let card = try self.card(containing: subtitle)
                XCTAssertGreaterThanOrEqual(
                    caption.convert(caption.bounds, to: card).minY, subtitle.convert(subtitle.bounds, to: card).maxY,
                    "\(name): «Эта неделя» still beside the headline"
                )
                XCTAssertEqual(caption.convert(caption.bounds, to: card).minX, 20, accuracy: 0.01, name)
                try assertNothingClipped(in: screen, name)

                let streak = screen.controller.streakBigLabel
                streak.text = "1234"
                screen.controller.streakBigWordLabel.text = StreakModalViewController.dayWord(for: 1234)
                screen.window.layoutIfNeeded()
                XCTAssertFalse(isClipped(streak), "\(name): a 4-digit streak crossed its floor")
                XCTAssertFalse(isClipped(screen.controller.streakBigWordLabel), "\(name): the day word is clipped")
            }
        }
    }

    /// Below XL the trend summary keeps today's row, and beside the long
    /// no-change subtitle «Эта неделя» keeps its whole line: on main the two
    /// tied at 750 and a cold open cut it to 37pt (#519 meant the headline
    /// column to give way).
    func testBelowXLTheTrendSummaryKeepsItsRowAndItsCaptionWhole() throws {
        for category in [UIContentSizeCategory.extraSmall, .medium, .large] {
            for width in [narrow, wide] {
                let screen = try hosted(category, width: width)
                let name = "\(category.rawValue) at \(width)"
                let caption = try label(Localized.text("statistics.trend.week_caption"), in: screen.view)
                let headline = screen.controller.trendHeadlineLabel
                let card = try self.card(containing: headline)
                XCTAssertEqual(
                    caption.convert(caption.bounds, to: card).minY, headline.convert(headline.bounds, to: card).minY,
                    accuracy: 0.01, "\(name): «Эта неделя» left the headline's row"
                )
                XCTAssertEqual(caption.textAlignment, .right)
                XCTAssertGreaterThanOrEqual(caption.bounds.width + 0.5, naturalWidth(of: caption), name)
                try assertNothingClipped(in: screen, name)
            }
        }
    }

    // MARK: - Live change and cold start

    /// The user changes the text size with the tab open, both ways: the
    /// attributed caps, title and headline are rebuilt with their tracking
    /// re-proportioned, the trend row restacks, and the way back lands on
    /// today's pinned geometry.
    func testALiveCategoryChangeGrowsTheTabAndReturnsToToday() throws {
        for width in [narrow, wide] {
            let screen = try hosted(.large, width: width, subtitle: Self.shortSubtitle)
            set(screen, to: Self.ax5)
            let caps = try attributes(of: label(Localized.text("statistics.trend.caps"), in: screen.view))
            XCTAssertGreaterThan(caps.font.pointSize, AppTypography.caps.pointSize, "the caps were not rebuilt")
            XCTAssertEqual(
                caps.kern / caps.font.pointSize, AppTypography.capsKerning / AppTypography.caps.pointSize,
                accuracy: 0.0001
            )
            let title = try attributes(of: label(Localized.text("statistics.title"), in: screen.view))
            XCTAssertGreaterThan(title.font.pointSize, AppTypography.h1.pointSize, "the title was not rebuilt")
            XCTAssertEqual(title.kern, -0.02 * title.font.pointSize, accuracy: 0.0001)
            XCTAssertGreaterThan(
                try font(of: screen.controller.weekdayHeadlineLabel).pointSize, AppTypography.h3.pointSize,
                "the weekday headline was not rebuilt"
            )
            try assertNothingClipped(in: screen, "live AX5 at \(width)")

            set(screen, to: .large)
            try assertTodaysGeometry(screen, width: width)
        }
    }

    /// A user who already runs a large size opens the tab: the first layout
    /// is the grown one, frame for frame the same as after a live change; and
    /// the way back matches a cold open at today's size. With the long
    /// subtitle, which makes both wrapping trend labels re-measure.
    func testAColdStartMatchesALiveChangeBothWays() throws {
        for width in [narrow, wide] {
            let cold = try hosted(Self.ax5, width: width)
            let live = try hosted(.large, width: width)
            set(live, to: Self.ax5)
            try assertSameLabelFrames(cold, live, "AX5 at \(width)")
            try assertNothingClipped(in: cold, "cold AX5 at \(width)")

            set(live, to: .large)
            try assertSameLabelFrames(try hosted(.large, width: width), live, "back to large at \(width)")
        }
    }

    // MARK: - Fixture

    fileprivate struct Screen {
        let window: UIWindow
        let controller: StatisticsViewController
        var view: UIView { controller.view }
    }

    private final class NoopScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }

    private var dayWord: String { StreakModalViewController.dayWord(for: 12) }
    private var lastSlip: String { Localized.format("statistics.last_slip", "28 сентября") }

    /// The tab on its own stores, in a window at `category`. Three snoozes on
    /// the last Wednesday make it the worst weekday, so the headline the view
    /// model renders is the same every day.
    private func hosted(
        _ category: UIContentSizeCategory, width: CGFloat, subtitle: String = longSubtitle
    ) throws -> Screen {
        let defaults = makeIsolatedDefaults()
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(.rub), .frozen(.rub))
        let wakes = WakeEventStore(defaults: defaults)
        let repository = TransactionRepository(defaults: defaults, wakeStore: wakes)
        let calendar = StatisticsViewModel.mondayFirstCalendar
        var wednesday = calendar.startOfDay(for: Date())
        repeat {
            wednesday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: wednesday))
        } while calendar.component(.weekday, from: wednesday) != 4
        let noon = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: wednesday))
        for _ in 0..<3 {
            XCTAssertTrue(repository.record(Transaction(type: .charge, amount: 50, currency: .rub, createdAt: noon)))
        }
        let alarms = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())
        XCTAssertTrue(alarms.save(Alarm(penaltyAmount: 50)))
        let model = StatisticsViewModel(
            repository: repository, wakeStore: wakes, alarmRepository: alarms, defaults: defaults, calendar: calendar
        )
        let controller = StatisticsViewController(viewModel: model)
        #if DEBUG
        controller.referralShortcutEnabled = false
        controller.referralControllerFactory = {
            XCTFail("the Dynamic Type harness must not open the referral flow")
            return ReferralViewController(personalCodeProvider: { "DYNTYPE" })
        }
        #endif
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 874)
        window.traitOverrides.preferredContentSizeCategory = category
        hostWindows.append(window)
        window.rootViewController = controller
        // Unhiding runs `viewWillAppear`, which sets the real texts; nothing
        // has been laid out yet, so the fixture's texts get the first layout.
        window.isHidden = false
        applyFixture(to: controller, subtitle: subtitle)
        window.layoutIfNeeded()
        XCTAssertEqual(controller.traitCollection.preferredContentSizeCategory, category, "override did not land")
        XCTAssertFalse(controller.scrollView.isHidden, "the cards are not on screen")
        XCTAssertEqual(model.worstWeekdayNames.count, 1, "the seeded Wednesday is not the only worst day")
        return Screen(window: window, controller: controller)
    }

    /// Replaces the date-dependent content with the values main was measured
    /// with. Before the first layout, as `viewWillAppear` does with the real
    /// ones: the two wrapping trend labels keep the width of the text they
    /// first laid out (`SPWrappingLabel`), so a fixture set after it would be
    /// measured against whatever this week's copy happened to be.
    private func applyFixture(to controller: StatisticsViewController, subtitle: String) {
        controller.streakBigLabel.text = "12"
        controller.streakBigWordLabel.text = dayWord
        controller.streakMetaLabel.text = lastSlip
        let calendar = StatisticsViewModel.mondayFirstCalendar
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? Date()
        let statuses: [StatisticsViewModel.DayStatus] = [.woke, .light, .heavy, .empty]
        controller.heatmapView.days = (0..<35).map { offset in
            StatisticsViewModel.HeatmapDay(
                date: calendar.date(byAdding: .day, value: offset, to: june) ?? june,
                status: statuses[offset % 4], snoozes: offset % 4, spent: 0, isInCurrentMonth: offset < 30
            )
        }
        let averages: [Double] = [0, 1.5, 2.5, 0.5, 1, 0, 0.3]
        controller.weekdayBarsView.stats = zip(StatisticsViewModel.weekdayShortLabels, averages).map {
            StatisticsViewModel.WeekdayStat(label: $0, average: $1, isWorst: $1 == 2.5)
        }
        controller.trendHeadlineLabel.text = Localized.text("statistics.trend.worse")
        controller.trendSubtitleLabel.text = subtitle
        controller.trendWeekValueLabel.text = "12"
        controller.trendArrowView.isHidden = false
        controller.trendBarsView.apply(
            points: [3, 5, 2, 4, 6, 1, 3, 12].enumerated().map { .init(count: $1, isCurrent: $0 == 7) },
            direction: .worse
        )
    }

    private func set(_ screen: Screen, to category: UIContentSizeCategory) {
        screen.window.traitOverrides.preferredContentSizeCategory = category
        screen.window.updateTraitsIfNeeded()
        screen.window.layoutIfNeeded()
        XCTAssertEqual(
            screen.controller.trendBarsView.traitCollection.preferredContentSizeCategory, category,
            "override did not reach the cards"
        )
    }
}

// MARK: - Today's geometry (main 65cd789e)

private extension StatisticsDynamicTypeTests {

    /// A frame measured on main. `width == nil` for a label whose width now
    /// comes from a `.fill` stack — see `testAtTheDefaultSizeTheTabIsUnchanged`.
    struct Pin {
        let view: UIView
        let root: UIView
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat?
        let height: CGFloat
    }

    func assertTodaysGeometry(_ screen: Screen, width: CGFloat) throws {
        let controller = screen.controller
        let header = try XCTUnwrap(descendants(of: SPPageHeader.self, in: screen.view).first)
        XCTAssertEqual(header.bounds.height, 76, accuracy: 0.01, "header at \(width)")
        XCTAssertEqual(try XCTUnwrap(controller.heroCard).bounds.height, width == narrow ? 485 : 505, accuracy: 0.01)
        XCTAssertEqual(try card(containing: controller.weekdayBarsView).bounds.height, 262, accuracy: 0.01)
        XCTAssertEqual(try card(containing: controller.trendBarsView).bounds.height, 281 + 1.0 / 3, accuracy: 0.01)
        let title = try label(Localized.text("statistics.title"), in: header)
        XCTAssertEqual(try font(of: title).pointSize, AppTypography.h1.pointSize)
        XCTAssertEqual(controller.streakBigLabel.font.pointSize, AppTypography.moneyXl.pointSize)
        XCTAssertEqual(controller.streakBigWordLabel.font.pointSize, AppTypography.h3.pointSize)
        XCTAssertEqual(try font(of: controller.weekdayHeadlineLabel).pointSize, AppTypography.h3.pointSize)

        let pins = [Pin(view: title, root: header, x: 16, y: 16, width: 182 + 2.0 / 3, height: 44)]
            + (try heroPins(screen, width: width))
            + (try weekdayPins(screen, width: width))
            + (try trendPins(screen, width: width))
        for pin in pins {
            let frame = pin.view.convert(pin.view.bounds, to: pin.root)
            let text = (pin.view as? UILabel).map { "«\($0.attributedText?.string ?? "")»" }
            let name = (text ?? "\(type(of: pin.view))") + " at \(width)"
            XCTAssertEqual(frame.minX, pin.x, accuracy: 0.01, "\(name): x")
            XCTAssertEqual(frame.minY, pin.y, accuracy: 0.01, "\(name): y")
            if let expected = pin.width {
                XCTAssertEqual(frame.width, expected, accuracy: 0.01, "\(name): width")
            }
            XCTAssertEqual(frame.height, pin.height, accuracy: 0.01, "\(name): height")
        }
    }

    /// Inside the 16pt screen insets and the cards' 20pt margins: 303 / 330.
    func content(_ width: CGFloat) -> CGFloat { width - 72 }

    func heroPins(_ screen: Screen, width: CGFloat) throws -> [Pin] {
        let controller = screen.controller
        let hero = try XCTUnwrap(controller.heroCard)
        let heatmap = controller.heatmapView
        let content = self.content(width)
        let side: CGFloat = width == narrow ? 39 : 43
        let legendY: CGFloat = width == narrow ? 407 + 2.0 / 3 : 427 + 2.0 / 3
        return [
            Pin(view: try label(Localized.text("statistics.streak.caps"), in: hero), root: hero,
                x: 20, y: 24, width: nil, height: 16 + 2.0 / 3),
            Pin(view: controller.streakBigLabel, root: hero, x: 20, y: 44 + 2.0 / 3, width: 67 + 1.0 / 3, height: 74),
            Pin(view: controller.streakBigWordLabel, root: hero,
                x: 95 + 1.0 / 3, y: 80 + 1.0 / 3, width: nil, height: 27 + 1.0 / 3),
            Pin(view: controller.streakMetaLabel, root: hero, x: 20, y: 126 + 2.0 / 3, width: nil, height: 18),
            Pin(view: heatmap, root: hero,
                x: 20, y: 164 + 2.0 / 3, width: content, height: width == narrow ? 231 : 251),
            Pin(view: try label("ПН", in: heatmap), root: heatmap,
                x: 0, y: 0, width: (content + 4) / 7 - 4, height: 16),
            Pin(view: try firstHeatmapCell(in: screen), root: heatmap, x: 0, y: 20, width: side, height: side),
            Pin(view: try label(Localized.text("statistics.streak.legend"), in: hero), root: hero,
                x: 20, y: legendY, width: content, height: 53 + 1.0 / 3),
            Pin(view: try XCTUnwrap(descendants(of: SPGradientView.self, in: hero).first), root: hero,
                x: content + 20 - 56, y: 24, width: 56, height: 56)
        ]
    }

    func weekdayPins(_ screen: Screen, width: CGFloat) throws -> [Pin] {
        let bars = screen.controller.weekdayBarsView
        let weekday = try card(containing: bars)
        let column = (content(width) - 48) / 7
        return [
            Pin(view: try label(Localized.text("statistics.weekday.caps"), in: weekday), root: weekday,
                x: 20, y: 20, width: nil, height: 16 + 2.0 / 3),
            Pin(view: screen.controller.weekdayHeadlineLabel, root: weekday,
                x: 20, y: 44 + 2.0 / 3, width: nil, height: 27 + 1.0 / 3),
            Pin(view: try label(Localized.text("statistics.weekday.meta"), in: weekday), root: weekday,
                x: 20, y: 76, width: nil, height: 18),
            Pin(view: bars, root: weekday, x: 20, y: 110, width: content(width), height: 132),
            Pin(view: try label("2,5", in: bars), root: bars, x: 2 * (column + 8), y: 0, width: column, height: 14),
            Pin(view: try label("Пн", in: bars), root: bars, x: 0, y: 118, width: column, height: 14)
        ]
    }

    func trendPins(_ screen: Screen, width: CGFloat) throws -> [Pin] {
        let controller = screen.controller
        let trend = try card(containing: controller.trendBarsView)
        let content = self.content(width)
        let axisLeft: CGFloat = width == narrow ? 151 + 2.0 / 3 : 165
        let caption: CGFloat = 71 + 2.0 / 3
        return [
            Pin(view: try label(Localized.text("statistics.trend.caps"), in: trend), root: trend,
                x: 20, y: 20, width: content, height: 16 + 2.0 / 3),
            Pin(view: controller.trendHeadlineLabel, root: trend,
                x: 20, y: 44 + 2.0 / 3, width: 141, height: 54 + 2.0 / 3),
            Pin(view: controller.trendArrowView, root: trend,
                x: 169, y: 65, width: 15 + 1.0 / 3, height: 14 + 1.0 / 3),
            Pin(view: controller.trendSubtitleLabel, root: trend,
                x: 20, y: 101 + 1.0 / 3, width: 132 + 2.0 / 3, height: 18),
            Pin(view: try label(Localized.text("statistics.trend.week_caption"), in: trend), root: trend,
                x: content + 20 - caption, y: 44 + 2.0 / 3, width: caption, height: 18),
            Pin(view: controller.trendWeekValueLabel, root: trend,
                x: content + 20 - 24, y: 64 + 2.0 / 3, width: 24, height: 26 + 2.0 / 3),
            Pin(view: controller.trendBarsView, root: trend, x: 20, y: 135 + 1.0 / 3, width: content, height: 100),
            Pin(view: try label(Localized.text("statistics.trend.axis_start"), in: trend), root: trend,
                x: 20, y: 243 + 1.0 / 3, width: axisLeft, height: 18),
            Pin(view: try label(Localized.text("statistics.trend.axis_end"), in: trend), root: trend,
                x: 20 + axisLeft, y: 243 + 1.0 / 3, width: content - axisLeft, height: 18)
        ]
    }
}

// MARK: - Lookup and clipping (as in AlarmsListDynamicTypeTests)

private extension StatisticsDynamicTypeTests {

    func card(containing view: UIView) throws -> SPCard {
        var current = view.superview
        while let candidate = current, !(candidate is SPCard) { current = candidate.superview }
        return try XCTUnwrap(current as? SPCard, "\(type(of: view)) is not in a card")
    }

    func firstHeatmapCell(in screen: Screen) throws -> UIView {
        try XCTUnwrap(
            screen.controller.heatmapView.subviews.first { String(describing: type(of: $0)) == "HeatmapDayCell" }
        )
    }

    /// The page header and the three cards of this slice — what it scales.
    func scaledRoots(in screen: Screen) throws -> [UIView] {
        let controller = screen.controller
        return [
            try XCTUnwrap(descendants(of: SPPageHeader.self, in: screen.view).first),
            try XCTUnwrap(controller.heroCard),
            try card(containing: controller.weekdayBarsView),
            try card(containing: controller.trendBarsView)
        ]
    }

    /// Visible, non-empty labels of the slice, keyed by root, text and slot.
    func labelFrames(in screen: Screen) throws -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for (index, root) in try scaledRoots(in: screen).enumerated() {
            for label in visibleLabels(in: root) {
                let key = "\(index)|\(label.attributedText?.string ?? "")|\(label.frame.minX)"
                frames[key] = label.convert(label.bounds, to: root)
            }
        }
        return frames
    }

    func assertSameLabelFrames(
        _ cold: Screen, _ live: Screen, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let coldFrames = try labelFrames(in: cold)
        let liveFrames = try labelFrames(in: live)
        XCTAssertGreaterThanOrEqual(coldFrames.count, 30, "too few labels to say anything", file: file, line: line)
        XCTAssertEqual(coldFrames.count, liveFrames.count, name, file: file, line: line)
        for (key, frame) in coldFrames {
            let other = try XCTUnwrap(liveFrames[key], "\(name): «\(key)» missing", file: file, line: line)
            let pairs = [(frame.minX, other.minX), (frame.minY, other.minY),
                         (frame.width, other.width), (frame.height, other.height)]
            for (expected, actual) in pairs {
                XCTAssertEqual(actual, expected, accuracy: 0.01, "\(name): «\(key)» \(other) vs cold \(frame)",
                               file: file, line: line)
            }
        }
    }

    func visibleLabels(in root: UIView) -> [UILabel] {
        descendants(of: UILabel.self, in: root).filter { label in
            guard !(label.attributedText?.string ?? "").isEmpty else { return false }
            var view: UIView? = label
            while let current = view, current !== root {
                if current.isHidden { return false }
                view = current.superview
            }
            return true
        }
    }

    func label(_ text: String, in root: UIView) throws -> UILabel {
        try XCTUnwrap(
            descendants(of: UILabel.self, in: root).first { ($0.attributedText?.string ?? $0.text) == text },
            "no label «\(text)»"
        )
    }

    func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        root.subviews.flatMap { [$0 as? T].compactMap { $0 } + descendants(of: type, in: $0) }
    }

    /// The font the label actually draws — the attributed run's, where one is set.
    func font(of label: UILabel) throws -> UIFont {
        let font = label.attributedText.flatMap { text in
            text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont : nil
        }
        return try XCTUnwrap(font ?? label.font)
    }

    func attributes(of label: UILabel) throws -> (font: UIFont, kern: CGFloat) {
        let text = try XCTUnwrap(label.attributedText)
        return (
            try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont),
            try XCTUnwrap(text.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat)
        )
    }

    func assertNothingClipped(
        in screen: Screen, _ name: String = "", file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let labels = try scaledRoots(in: screen).flatMap(visibleLabels(in:))
        XCTAssertGreaterThanOrEqual(labels.count, 30, "too few labels to say anything", file: file, line: line)
        for label in labels {
            XCTAssertFalse(
                isClipped(label), "\(name): «\(label.attributedText?.string ?? "")» is clipped: \(label.bounds)",
                file: file, line: line
            )
        }
    }

    /// Measured against unlimited lines at the label's width, not against its
    /// own `numberOfLines` — a capped label would "fit" its truncated text.
    /// A one-line shrink-to-fit label (the streak count, the chart labels) is
    /// clipped only when even its minimum scale overflows the width.
    /// A wrapping label is clipped too when one of its words is wider than the
    /// label: UIKit then breaks it mid-word, which the height check cannot see.
    func isClipped(_ label: UILabel) -> Bool {
        if label.numberOfLines == 1 && label.adjustsFontSizeToFitWidth {
            return naturalWidth(of: label) * label.minimumScaleFactor > label.bounds.width + 0.5
        }
        let unlimited = label.textRect(
            forBounds: CGRect(x: 0, y: 0, width: label.bounds.width, height: .greatestFiniteMagnitude),
            limitedToNumberOfLines: 0
        )
        if unlimited.height > label.bounds.height + 0.5 { return true }
        return label.numberOfLines != 1 && widestWord(of: label) > label.bounds.width + 0.5
    }

    func widestWord(of label: UILabel) -> CGFloat {
        guard let text = label.attributedText, text.length > 0 else { return 0 }
        let attributes = text.attributes(at: 0, effectiveRange: nil)
        // Only where UIKit may break a line: U+202F and U+00A0 keep a price whole.
        return text.string.split(whereSeparator: { $0 == " " || $0.isNewline }).map { word in
            NSAttributedString(string: String(word), attributes: attributes).size().width
        }.max() ?? 0
    }

    func naturalWidth(of label: UILabel) -> CGFloat {
        let infinite = CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        return label.textRect(forBounds: infinite, limitedToNumberOfLines: 1).width
    }

    /// The point size a shrink-to-fit label actually draws at.
    func drawnPointSize(of label: UILabel) throws -> CGFloat {
        let scale = min(1, label.bounds.width / naturalWidth(of: label))
        return try font(of: label).pointSize * scale
    }
}
