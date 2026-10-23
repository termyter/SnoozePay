import UIKit
import XCTest
@testable import SnoozePay

final class WakeHistoryAvailabilityTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let calendar = StatisticsViewModel.mondayFirstCalendar
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 1, day: 27, hour: 7))! }

    override func setUp() {
        super.setUp()
        suiteName = "test.wakeAvailability.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func put(_ dates: [Date], key: String) throws {
        defaults.set(try JSONEncoder().encode(dates), forKey: key)
    }

    private func model() -> StatisticsViewModel {
        let store = WakeEventStore(defaults: defaults)
        return StatisticsViewModel(
            repository: TransactionRepository(defaults: defaults, wakeStore: store),
            wakeStore: store, alarmRepository: AlarmRepository(defaults: defaults),
            defaults: defaults, calendar: calendar
        )
    }

    private func strings(_ view: UIView, includeHidden: Bool = false) -> [String] {
        guard includeHidden || !view.isHidden else { return [] }
        let label = view as? UILabel
        return [label?.text, label?.attributedText?.string].compactMap { $0 }
            + view.subviews.flatMap { strings($0, includeHidden: includeHidden) }
    }

    func testSnapshotDistinguishesMissingEmptyAndLegacyDayOnlyHistory() throws {
        let store = WakeEventStore(defaults: defaults)
        XCTAssertEqual(store.readSnapshot(), .init(days: .missing, times: .missing))
        try put([], key: "wake_days")
        XCTAssertEqual(store.readSnapshot(), .init(days: .value([]), times: .missing))
        try put([], key: "wake_times")
        XCTAssertEqual(store.readSnapshot(), .init(days: .value([]), times: .value([])))
        defaults.removeObject(forKey: "wake_times")
        let day = calendar.startOfDay(for: today)
        try put([day], key: "wake_days")
        let viewModel = model()
        viewModel.loadData()
        viewModel.recomputeSnapshots(today: today)
        XCTAssertEqual(viewModel.wakeDays, [day])
        XCTAssertEqual(viewModel.wakeTimeAvailability, .noRecentHistory)
        XCTAssertNil(viewModel.overviewUnavailableReason)
        XCTAssertNil(defaults.object(forKey: "wake_times"), "A legacy read must not manufacture timestamps")
    }

    func testEachUnreadableKeyPreservesItsRawValueAndHealthySibling() throws {
        let store = WakeEventStore(defaults: defaults)
        for key in ["wake_days", "wake_times"] {
            let sibling = key == "wake_days" ? "wake_times" : "wake_days"
            for raw in [Data("not json".utf8), Data("{}".utf8), "wrong defaults type"] as [Any] {
                defaults.set(raw, forKey: key)
                try put([today], key: sibling)
                let before = defaults.persistentDomain(forName: suiteName)! as NSDictionary
                let snapshot = store.readSnapshot()
                XCTAssertEqual(key == "wake_days" ? snapshot.days : snapshot.times, .unreadable)
                XCTAssertEqual(key == "wake_days" ? snapshot.times : snapshot.days, .value([today]))
                _ = store.wakeDays()
                _ = store.wakeTimes()
                XCTAssertEqual(defaults.persistentDomain(forName: suiteName)! as NSDictionary, before)
            }
        }
    }

    func testTypedAggregationKeepsZeroShortFiveAndRefusedStatesDistinct() {
        for count in [0, 1, 4, 5] {
            let times = (0..<count).map { calendar.date(byAdding: .day, value: -$0, to: today)! }
            let state = StatisticsViewModel.wakeTimeAvailability(today: today, wakeTimes: times, calendar: calendar)
            if count == 0 {
                XCTAssertEqual(state, .noRecentHistory)
            } else if count < 5 {
                guard case .accumulating(let stats) = state else { return XCTFail("short history: \(state)") }
                XCTAssertNil(stats.medianMinutes)
                XCTAssertEqual(stats.samplesUntilReady, 5 - count)
            } else {
                guard case .available(let stats) = state else { return XCTFail("five mornings: \(state)") }
                XCTAssertEqual(stats.medianMinutes, 420)
            }
        }
        for (median, count) in [(1440, 1), (1440, 5), (nil, 5)] as [(Int?, Int)] {
            let stats = StatisticsViewModel.WakeTimeStats(
                medianMinutes: median, baselineMedianMinutes: nil, recentSampleCount: count, minimumSamples: 5
            )
            XCTAssertEqual(
                StatisticsViewModel.WakeTimeAvailability(stats: stats), .unavailable(.calculationUnavailable)
            )
        }
    }

    func testUnreadableDaysWithholdOverviewAndPreserveBestStreakAndBothBlobs() throws {
        let corrupt = Data("broken days".utf8)
        defaults.set(corrupt, forKey: "wake_days")
        try put([today], key: "wake_times")
        let timesBefore = defaults.data(forKey: "wake_times")
        defaults.set(7, forKey: "best_streak")
        defaults.set(try JSONEncoder().encode([Transaction(type: .charge, amount: 50, createdAt: today)]),
                     forKey: "stored_transactions")
        let viewModel = model()
        viewModel.loadData()
        viewModel.recomputeSnapshots(today: today)
        XCTAssertTrue(viewModel.ledgerReadable)
        XCTAssertEqual(viewModel.charges.count, 1)
        XCTAssertEqual(viewModel.overviewUnavailableReason, .wakeHistoryUnreadable)
        XCTAssertTrue(viewModel.heatmapDays.isEmpty)
        XCTAssertTrue(viewModel.weekMoneyDays.isEmpty)
        XCTAssertNil(viewModel.weekMoneySummary.saved)
        XCTAssertEqual(viewModel.streak, 0)
        XCTAssertEqual(defaults.integer(forKey: "best_streak"), 7)
        XCTAssertEqual(defaults.data(forKey: "wake_days"), corrupt)
        XCTAssertEqual(defaults.data(forKey: "wake_times"), timesBefore)
        defaults.set(Data("broken times".utf8), forKey: "wake_times")
        viewModel.loadData()
        XCTAssertEqual(viewModel.overviewUnavailableReason, .wakeHistoryUnreadable)
        defaults.set(Data("broken ledger".utf8), forKey: "stored_transactions")
        viewModel.loadData()
        XCTAssertEqual(viewModel.overviewUnavailableReason, .ledger(.ledgerUnreadable))
        defaults.set(try JSONEncoder().encode([Transaction(type: .unknown("future"), amount: 50)]),
                     forKey: "stored_transactions")
        viewModel.loadData()
        XCTAssertEqual(viewModel.overviewUnavailableReason, .ledger(.ledgerPartiallyRead))
    }

    func testTimeOnlyFailureKeepsDayStatisticsAndReloadClearsFailure() throws {
        try put([calendar.startOfDay(for: today)], key: "wake_days")
        let corrupt = Data("broken times".utf8)
        defaults.set(corrupt, forKey: "wake_times")
        let viewModel = model()
        viewModel.loadData()
        viewModel.recomputeSnapshots(today: today)
        XCTAssertNil(viewModel.overviewUnavailableReason)
        XCTAssertEqual(viewModel.wakeTimeAvailability, .unavailable(.historyUnreadable))
        XCTAssertFalse(viewModel.weekMoneySummary.isEmpty)
        XCTAssertTrue(viewModel.heatmapDays.contains { $0.status == .woke })
        XCTAssertEqual(defaults.data(forKey: "wake_times"), corrupt)
        // External fixture replacement, not an in-app recovery operation.
        try put([today], key: "wake_times")
        viewModel.recomputeSnapshots(today: today)
        XCTAssertEqual(viewModel.wakeTimeAvailability, .unavailable(.historyUnreadable),
                       "Recomputation must use its captured read, not mix in a newer store")
        viewModel.loadData()
        viewModel.recomputeSnapshots(today: today)
        XCTAssertEqual(viewModel.wakeTimeStats?.recentSampleCount, 1)
        XCTAssertNil(viewModel.wakeTimeStats?.medianMinutes)
    }

    func testControllerDoesNotHideTimesFailureBehindHealthyEmptyCopy() throws {
        let corrupt = Data("broken times".utf8)
        defaults.set(corrupt, forKey: "wake_times")
        let viewModel = model()
        let controller = StatisticsViewController(viewModel: viewModel)
        controller.loadViewIfNeeded()
        viewModel.loadData()
        XCTAssertTrue(controller.scrollView.isHidden)
        XCTAssertFalse(controller.emptyState.isHidden)
        XCTAssertTrue(strings(controller.emptyState).contains("Не удалось прочитать историю подъёмов."))
        XCTAssertFalse(strings(controller.emptyState).contains(Localized.text("statistics.empty.body")))
        XCTAssertEqual(defaults.data(forKey: "wake_times"), corrupt)
        try put([calendar.startOfDay(for: today)], key: "wake_days")
        viewModel.loadData()
        XCTAssertFalse(controller.scrollView.isHidden)
        XCTAssertFalse(controller.wakeTimeCard.isHidden)
        XCTAssertTrue(strings(controller.wakeTimeCard).contains("Не удалось прочитать историю подъёмов."))
    }

    func testCardReuseExplainsFailuresAndClearsHiddenNumbersInBothThemes() {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let card = SPWakeTimeCard()
            card.overrideUserInterfaceStyle = style
            let valid = StatisticsViewModel.WakeTimeStats(
                medianMinutes: 420, baselineMedianMinutes: 480, recentSampleCount: 5, minimumSamples: 5
            )
            card.apply(valid)
            card.apply(StatisticsViewModel.WakeTimeAvailability.unavailable(.historyUnreadable))
            XCTAssertTrue(strings(card).contains("Не удалось прочитать историю подъёмов."))
            XCTAssertFalse(strings(card, includeHidden: true).contains(StatisticsViewModel.clockText(minutes: 420)))
            let badBaseline = StatisticsViewModel.WakeTimeStats(
                medianMinutes: 420, baselineMedianMinutes: 1440, recentSampleCount: 5, minimumSamples: 5
            )
            card.apply(badBaseline)
            XCTAssertTrue(strings(card).contains(StatisticsViewModel.clockText(minutes: 420)))
            XCTAssertTrue(strings(card).contains("Сравнение времени подъёма недоступно."))
            XCTAssertFalse(strings(card).contains(Localized.text("statistics.wake_time.pending")))
            card.apply(valid)
            XCTAssertTrue(strings(card).contains(StatisticsViewModel.clockText(minutes: 480)))
            XCTAssertFalse(strings(card, includeHidden: true).contains("Сравнение времени подъёма недоступно."))
        }
    }

    func testUnavailableCopyShipsWithExactRussianAndEnglishWords() throws {
        let copy = [
            "statistics.wake_time.unreadable": ["ru": "Не удалось прочитать историю подъёмов.",
                                                "en": "Your wake-up history couldn’t be read."],
            "statistics.wake_time.calculation_unavailable": [
                "ru": "Не удалось рассчитать время подъёма по записанной истории.",
                "en": "Your wake-up time couldn’t be calculated from the recorded history."],
            "statistics.wake_time.comparison_unavailable": ["ru": "Сравнение времени подъёма недоступно.",
                                                           "en": "The wake-up time comparison is unavailable."]
        ]
        for (key, translations) in copy {
            for (language, expected) in translations {
                let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
                let bundle = try XCTUnwrap(Bundle(path: path))
                XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), expected)
            }
        }
    }
}
