#if DEBUG
import UIKit

/// DEBUG-only screen router for automated visual audits.
///
/// Launching the app with `-uitour <screen>` mounts the requested screen
/// directly as the window root — bypassing splash, onboarding and tab
/// navigation — so an audit script can screenshot every screen without
/// tapping through the UI (no UI-automation tooling required).
///
/// This file is the *mechanics*: argument parsing, seeding, and the root
/// view-controller swap. **The screen list itself lives in `UITourRoutes`**
/// (split out in #564, when this file hit the `file_length` ceiling) — that is
/// where you add a route and where the supported ids are documented.
///
/// Optional arguments:
///   `-uitour-reset`          wipe persisted alarms before mounting (clean state)
///   `-uitour-seed`           seed demo alarms / transactions / wake history
///   `-uitour-balance <n>`    force balance to exactly n ₽ (via service APIs)
///   `-uitour-theme <id>`     firing-screen `AlarmTheme`, NOT the light/dark
///                            appearance: dawn|ocean|mountains|forest|neon|abstract
///   `-uitour-appearance <id>` window appearance: light|dark. Beats the
///                            `preferred_theme` stuck in the sandbox — what
///                            made "both themes" runs check one theme twice
///   `-uitour-backend-warning <case>`
///                            non-ringing state `alarms-nobackend` forces:
///                            unavailable|notrequested|indeterminate
///   `-uitour-alarmkit <state>`
///                            pin the AlarmKit backend: granted|denied. The
///                            only way an E2E run can have (or provably lack)
///                            alarm authorization — a simulator offers no way
///                            to set it. See `UITourAlarmKitBackend` (#606)
///   `-uitour-storekit-empty` pin the StoreKit catalogue empty so every top-up
///                            CTA takes its DEBUG local-credit fallback instead
///                            of the real `purchase(_:)` (#575). Read by
///                            `StoreKitService`, not by this file — the service
///                            loads at `AppDelegate` time, before any mount.
enum UITourLauncher {

    /// Spelled once so `isTourLaunch` and `requestedScreen` cannot drift.
    static let screenArgument = "-uitour"

    static var requestedScreen: String? { value(after: screenArgument) }

    /// `true` when `arguments` mount a tour screen. Read by `AppDelegate` to
    /// skip the launch-time permission re-ask (#626): a tour launch shows one
    /// screen and must never cover it with a dialog nobody asked for.
    ///
    /// Keyed on a value FOLLOWING the flag, not merely on the flag: a trailing
    /// `-uitour` with nothing after it mounts nothing, so the app is running
    /// normally and should behave normally.
    ///
    /// «A value» is literal — `value(after:in:)` takes the next argument
    /// whatever it is, so `["-uitour", "-uitour-balance", "1000"]` reads
    /// `"-uitour-balance"` as the screen id. That stays correct for this
    /// predicate rather than by luck: an unknown id still mounts something
    /// (`UITourRoutes.mounter(for:)` falls back to the tab bar), so a screen is
    /// on display and skipping the permission re-ask is still right. Do not
    /// «fix» this into a known-ids check without also deciding what an unknown
    /// id should mount.
    ///
    /// Pure over `arguments` so the rule is unit-testable without launching an
    /// app.
    static func isTourLaunch(arguments: [String]) -> Bool {
        value(after: screenArgument, in: arguments) != nil
    }

    // MARK: - Mounting

    static func mount(_ screen: String, in window: UIWindow) {
        // Before the mounters: a screen that pins its own appearance (firing,
        // splash) must be able to overrule the tour, not the other way round.
        applyAppearance(value(after: "-uitour-appearance"), to: window)
        // Before `resetIfRequested`, which cancels through the scheduler, and
        // well before any screen can save an alarm.
        applyForcedAlarmKitBackend()
        resetIfRequested()
        seedIfRequested()
        UITourRoutes.mounter(for: screen)(window)
    }

    // MARK: - Argument parsing

    /// `-uitour-backend-warning <case>` — which non-ringing state
    /// `alarms-nobackend` shows. Defaults to `.unavailable`: where a user
    /// lands after denying the prompt. `.available` / `.unresolved` are not
    /// reachable here — no banner is what plain `-uitour alarms` shows.
    /// Split from the `ProcessInfo` read so tests can walk every variant.
    static func backendAvailability(forArgument raw: String?) -> AlarmBackendAvailability {
        switch raw {
        case "notrequested": return .notRequested
        case "indeterminate": return .indeterminate
        default: return .unavailable
        }
    }

    static func requestedBackendAvailability() -> AlarmBackendAvailability {
        backendAvailability(forArgument: value(after: "-uitour-backend-warning"))
    }

    /// `-uitour-appearance light|dark` — pin the window's interface style.
    /// Writes ONLY the window, never `ThemeService`/`preferred_theme`: the next
    /// flag-less launch must read what the user left. An absent or unknown
    /// value leaves whatever `SceneDelegate` applied. Internal for tests.
    static func applyAppearance(_ raw: String?, to window: UIWindow) {
        switch raw {
        case "light": window.overrideUserInterfaceStyle = .light
        case "dark": window.overrideUserInterfaceStyle = .dark
        default: return
        }
    }

    /// Spelled once, here, because it is a contract with
    /// `CreateAlarmUITests.launchArguments` — a typo on either side silently
    /// puts that test back on ambient simulator state, which is what #606 was
    /// (`StoreKitService.emptyCatalogArgument` exists for the same reason).
    static let alarmKitArgument = "-uitour-alarmkit"

    /// The AlarmKit backend `arguments` pins, or `nil` for "leave the real one
    /// alone". Pure over `arguments` so a unit test can walk every spelling
    /// without launching an app.
    ///
    /// Opt-in by construction: anything other than the two known values —
    /// including no flag at all — must return `nil`, or a DEBUG build would
    /// start faking authorization for a human running the app by hand.
    static func forcedAlarmKitBackend(arguments: [String]) -> UITourAlarmKitBackend? {
        switch value(after: alarmKitArgument, in: arguments) {
        case "granted": return UITourAlarmKitBackend(isAuthorized: true)
        case "denied": return UITourAlarmKitBackend(isAuthorized: false)
        default: return nil
        }
    }

    /// Installs the pinned backend, if any. Idempotent, and called from BOTH
    /// `AppDelegate.didFinishLaunching` and `mount` — `AppDelegate` already
    /// asks the scheduler for permission before any scene exists, and on the
    /// real backend that ask can put a system prompt on screen mid-test.
    static func applyForcedAlarmKitBackend() {
        guard let backend = forcedAlarmKitBackend(
            arguments: ProcessInfo.processInfo.arguments
        ) else { return }
        AlarmScheduler.uiTourForcedBackend = backend
    }

    static func requestedTheme() -> AlarmTheme {
        switch value(after: "-uitour-theme") {
        case "ocean": return .ocean
        case "mountains": return .mountains
        case "forest": return .forest
        case "neon": return .neon
        case "abstract": return .abstract
        default: return .dawn
        }
    }

    private static func value(after flag: String) -> String? {
        value(after: flag, in: ProcessInfo.processInfo.arguments)
    }

    /// The `ProcessInfo`-free half, so parsing can be unit-tested.
    private static func value(after flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), args.count > idx + 1 else { return nil }
        return args[idx + 1]
    }

    // MARK: - Seeding

    /// `-uitour-reset` — wipe persisted alarms before mounting so a flow that
    /// asserts on list contents (e.g. the create-alarm e2e) starts from a known
    /// empty state. Simulator `UserDefaults` survive across `app.launch()`, so
    /// without this a previous run's alarms leak into the next test's counts.
    private static func resetIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-uitour-reset") else { return }
        let repo = AlarmRepository.shared
        // Checked read collapsed with `try?` (#271): a wipe driven by an
        // unreadable store would silently do nothing, and the tour must not
        // depend on the lossy fetcher.
        for alarm in (try? repo.fetchAllChecked()) ?? [] {
            _ = repo.delete(id: alarm.id)
        }
    }

    private static func seedIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("-uitour-seed") {
            seedAlarms()
            seedTransactions()
            seedWakeHistory()
        }
        if let raw = value(after: "-uitour-balance"), let target = Double(raw) {
            forceBalance(to: target)
        }
    }

    /// Demo alarms for `-uitour-seed`.
    ///
    /// # The three names below stay Swift literals (#598)
    ///
    /// They are the only Cyrillic literals left in this file and they are
    /// **not** copy, so they do not belong in `Localizable.xcstrings`. An
    /// alarm's name is user *content* — free text typed into
    /// `CreateAlarmViewController` and stored as `Alarm.customName`. These
    /// three fabricate a plausible set of it, the way the unit suite does:
    /// seven test files hardcode «Работа» for the same reason. Migrating them
    /// would hand a translator three demo alarm names to translate as though
    /// they were UI chrome, in a file that is otherwise the translation
    /// deliverable — and no key in the catalogue is content rather than copy.
    ///
    /// They are also unreachable from a shipped build: this whole file is
    /// `#if DEBUG`, and the names only ever render behind `-uitour-seed`.
    ///
    /// The default an *unnamed* alarm falls back to is a different thing and
    /// is copy: it reads the catalogue via ``Alarm/defaultName``. All three
    /// seeds above are named, so that default does not appear on these
    /// screens.
    private static func seedAlarms() {
        let repo = AlarmRepository.shared
        guard ((try? repo.fetchAllChecked()) ?? []).isEmpty else { return }
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        repo.save(Alarm(  // i18n:exempt имя будильника в фикстуре, не копия UI
            time: at(7, 30), repeatDays: [0, 1, 2, 3, 4], name: "Работа", penaltyAmount: 50
        ))
        repo.save(Alarm(  // i18n:exempt имя будильника в фикстуре, не копия UI
            time: at(9, 0), repeatDays: [5, 6], name: "Спортзал и длинная пробежка по набережной",
            penaltyAmount: 100, progressiveScale: true, theme: .ocean
        ))
        repo.save(Alarm(  // i18n:exempt имя будильника в фикстуре, не копия UI
            time: at(6, 15), repeatDays: [], name: "Рейс в Стамбул", penaltyAmount: 200,
            enabled: false, repeatMode: .never
        ))
    }

    private static func seedTransactions() {
        let repo = TransactionRepository.shared
        guard ((try? repo.fetchAllChecked()) ?? []).isEmpty else { return }
        let day: TimeInterval = 86_400
        let now = Date()
        let seeds: [(TransactionType, Double, Double)] = [
            (.topup, 500, 38), (.charge, 50, 35), (.charge, 50, 34),
            (.promotion, 200, 21), (.charge, 100, 16), (.topup, 250, 9),
            (.charge, 50, 5), (.charge, 50, 2), (.charge, 100, 0.3)
        ]
        for (type, amount, daysAgo) in seeds {
            repo.record(Transaction(type: type, amount: amount, createdAt: now.addingTimeInterval(-daysAgo * day)))
        }
    }

    private static func seedWakeHistory() {
        let store = WakeEventStore.shared
        let calendar = Calendar.current
        // Wake on ~2 of every 3 of the last 45 days — enough texture for the
        // heatmap, weekday bars and the 8-week trend to render all states.
        //
        // The recorded instant matters since #348: wake times drift ~1 min
        // earlier per day into the past, so the trailing two weeks average
        // out visibly earlier than the two before them and the "Раньше на N
        // мин" column has something honest to show in the tour.
        for daysAgo in 0...45 where daysAgo % 3 != 1 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) else { continue }
            let minutesLater = daysAgo + (daysAgo % 7) * 3
            let wakeTime = calendar.date(
                bySettingHour: 6, minute: 45, second: 0, of: day
            ).flatMap { calendar.date(byAdding: .minute, value: minutesLater, to: $0) }
            store.recordWake(on: wakeTime ?? day)
        }
    }

    static func forceBalance(to target: Double) {
        let service = BalanceService.shared
        let delta = target - service.balance
        if delta > 0 {
            _ = service.topUp(amount: delta)
        } else if delta < 0 {
            _ = service.charge(amount: -delta, alarmID: nil)
        }
    }
}
#endif
