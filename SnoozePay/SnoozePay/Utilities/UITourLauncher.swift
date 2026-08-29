#if DEBUG
import UIKit

/// DEBUG-only screen router for automated visual audits.
///
/// Launching the app with `-uitour <screen>` mounts the requested screen
/// directly as the window root — bypassing splash, onboarding and tab
/// navigation — so an audit script can screenshot every screen without
/// tapping through the UI (no UI-automation tooling required).
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
///
/// Supported screens: onboarding, permissions, alarms, alarms-nobackend,
/// wallet, stats, settings, create, edit, theme-picker, sound-picker,
/// volume-picker, confirm-delete, firing, firing-snoozed, firing-progressive,
/// firing-nobalance, firing-topup, alarm-off-warning, txhistory, periodpicker,
/// deposit, streak.
enum UITourLauncher {

    static var requestedScreen: String? { value(after: "-uitour") }

    // MARK: - Mounting

    static func mount(_ screen: String, in window: UIWindow) {
        // Before the mounters: a screen that pins its own appearance (firing,
        // splash) must be able to overrule the tour, not the other way round.
        applyAppearance(value(after: "-uitour-appearance"), to: window)
        resetIfRequested()
        seedIfRequested()
        // Unknown screen id — land on the alarms tab so the audit
        // screenshot makes the mistake obvious instead of hanging.
        let mounter = mounters[screen] ?? { $0.rootViewController = tabBar(selected: 0) }
        mounter(window)
    }

    /// Screen-id → mounter registry. A flat dictionary (instead of a switch)
    /// keeps `mount` trivially simple for the linter and makes the supported
    /// screen list greppable in one place.
    private static let mounters: [String: (UIWindow) -> Void] = [
        "onboarding": { window in
            // Mirror SceneDelegate's onboarding → permissions → main tab bar
            // chain so an e2e walk can run the whole first-launch journey end
            // to end (the production wiring lives in SceneDelegate, which the
            // -uitour direct mount bypasses).
            let onboarding = OnboardingViewController()
            onboarding.onFinished = { [weak window] in
                let permissions = PermissionsViewController()
                permissions.onFinished = { [weak window] in
                    window?.rootViewController = SceneDelegate.makeMainTabBar()
                }
                window?.rootViewController = permissions
            }
            window.rootViewController = onboarding
        },
        "permissions": { $0.rootViewController = PermissionsViewController() },
        "alarms": { $0.rootViewController = tabBar(selected: 0) },
        // The alarms list with the "будильники не зазвонят" banner up (#428).
        // Forced through the monitor's DEBUG seam *before* the tab bar builds
        // the VM. Which state you get: `-uitour-backend-warning`.
        "alarms-nobackend": { window in
            AlarmBackendMonitor.uiTourForcedAvailability = requestedBackendAvailability()
            window.rootViewController = tabBar(selected: 0)
        },
        // A pageSheet over the stats tab — NOT root-mounted. #514 was a crash
        // on OPENING this screen and #467 is a sheet that doesn't lay out:
        // presentation is itself the failure mode, so the route must run it.
        "alarm-off-warning": { mountPresented(makeAlarmOffWarningSheet(), onTab: 2, in: $0) },
        "wallet": { $0.rootViewController = tabBar(selected: 1) },
        "stats": { $0.rootViewController = tabBar(selected: 2) },
        "settings": { mountPushed(SettingsViewController(), onTab: 0, in: $0) },
        "create": { mountPresented(createNav(alarm: nil), onTab: 0, in: $0) },
        "edit": { mountPresented(createNav(alarm: sampleAlarm()), onTab: 0, in: $0) },
        "theme-picker": { window in
            mountPushedOnCreate(in: window) { theme in
                AlarmThemePickerViewController(currentTheme: theme, onSelect: { _ in })
            }
        },
        "sound-picker": { window in
            mountPushedOnCreate(in: window) { _ in
                SoundPickerViewController(
                    sounds: CreateAlarmViewModel(alarm: nil).availableSounds,
                    selectedID: "radar",
                    onSelect: { _ in },
                    previewSound: { _ in }
                )
            }
        },
        "volume-picker": { window in
            mountPushedOnCreate(in: window) { _ in
                VolumePickerViewController(volume: 0.7, fadeIn: true)
            }
        },
        "confirm-delete": { window in
            let nav = createNav(alarm: sampleAlarm())
            // Sequence, don't race (#467). Both presentations used to be
            // scheduled on the SAME 0.8 s deadline, so the sheet asked a
            // navigation controller that was still mid-transition to present:
            // a silent no-op, and every audit capture showed the scrim with an
            // empty strip instead of the confirmation. Chaining off the edit
            // form's own presentation completion guarantees the presenter is
            // already in the window hierarchy.
            mountPresented(nav, onTab: 0, in: window) {
                nav.present(ConfirmDeleteAlarmViewController(), animated: false)
            }
        },
        "firing": { $0.rootViewController = AlarmFiringViewController(alarm: firingSampleAlarm()) },
        "firing-progressive": {
            $0.rootViewController = AlarmFiringViewController(alarm: progressiveFiringAlarm())
        },
        "firing-snoozed": {
            $0.rootViewController = AlarmFiringViewController(alarm: firingSampleAlarm(), snoozeCount: 2)
        },
        "firing-nobalance": { window in
            forceBalance(to: 0)
            window.rootViewController = AlarmFiringViewController(alarm: firingSampleAlarm())
        },
        "firing-topup": { window in
            let firing = AlarmFiringViewController(alarm: firingSampleAlarm())
            window.rootViewController = firing
            presentLater(FiringTopUpBottomSheetViewController(), over: firing)
        },
        "txhistory": { mountPushed(WalletTransactionHistoryViewController(), onTab: 1, in: $0) },
        "periodpicker": { window in
            let history = WalletTransactionHistoryViewController()
            mountPushed(history, onTab: 1, in: window)
            presentLater(
                PeriodPickerSheetViewController(selected: nil, years: [2025, 2026], onApply: { _ in }),
                over: history
            )
        },
        "deposit": { window in
            let root = tabBar(selected: 1)
            window.rootViewController = root
            presentLater(DepositBottomSheetViewController(), over: root)
        },
        "streak": { window in
            let root = tabBar(selected: 2)
            window.rootViewController = root
            // Fixed 7 days / 350 ₽ — the `28-streak` artboard's numbers, so the
            // audit screenshot doesn't depend on whatever alarms the tour
            // device happens to hold.
            presentLater(
                StreakModalViewController(streakDays: 7, savedAmount: 350),
                over: root
            )
        }
    ]

    // MARK: - Roots

    private static func tabBar(selected index: Int) -> UIViewController {
        let tabBar = SceneDelegate.makeMainTabBar()
        (tabBar as? UITabBarController)?.selectedIndex = index
        return tabBar
    }

    private static func mountPushed(_ vc: UIViewController, onTab index: Int, in window: UIWindow) {
        let root = tabBar(selected: index)
        window.rootViewController = root
        let nav = (root as? UITabBarController)?
            .selectedViewController as? UINavigationController
        nav?.pushViewController(vc, animated: false)
    }

    /// Mounts a tab-bar root and presents `vc` over it. `then` runs only after
    /// that presentation has actually finished, which is the only safe moment
    /// to chain a second presentation or a push onto `vc` (#467).
    private static func mountPresented(
        _ vc: UIViewController,
        onTab index: Int,
        in window: UIWindow,
        then next: (() -> Void)? = nil
    ) {
        let root = tabBar(selected: index)
        window.rootViewController = root
        presentLater(vc, over: root, then: next)
    }

    private static func createNav(alarm: Alarm?) -> UINavigationController {
        let nav = AppNavigationBarStyle.makeNavigationController(
            rootViewController: CreateAlarmViewController(alarm: alarm)
        )
        nav.modalPresentationStyle = .fullScreen
        return nav
    }

    private static func mountPushedOnCreate(
        in window: UIWindow,
        makePicker: @escaping (AlarmTheme) -> UIViewController
    ) {
        let nav = createNav(alarm: sampleAlarm())
        // Same chaining as `confirm-delete`: one timer, then a completion —
        // never two timers sharing a deadline (#467).
        mountPresented(nav, onTab: 0, in: window) {
            nav.pushViewController(makePicker(.dawn), animated: false)
        }
    }

    /// Presents a sheet/modal after the root has had a beat to lay out —
    /// presenting from a VC that isn't in the hierarchy yet is a no-op.
    private static func presentLater(
        _ vc: UIViewController,
        over presenter: UIViewController,
        then next: (() -> Void)? = nil
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            (presenter.presentedViewController ?? presenter)
                .present(vc, animated: false, completion: next)
        }
    }

    // MARK: - Sample data

    private static func sampleAlarm() -> Alarm {
        Alarm(
            time: Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date(),
            repeatDays: [0, 1, 2, 3, 4], // Monday-first indices: Пн–Пт
            name: "Работа",
            penaltyAmount: 50,
            theme: requestedTheme()
        )
    }

    /// The firing-screen sample, anchored to the CURRENT time rather than a
    /// fixed 07:30. A firing alarm is, by definition, ringing *now*. The
    /// snoozed-state countdown now anchors to the snooze-tap moment
    /// (`AlarmFiringViewModel.nextRingDate` = tap + snoozeMinutes, issue #396),
    /// so the countdown stays positive regardless of the alarm's HH:MM — but a
    /// now-anchored time still keeps the firing clock and "ringing now" framing
    /// realistic for screenshots and the e2e firing→snooze→wake UI test.
    private static func firingSampleAlarm() -> Alarm {
        Alarm(
            time: Date(),
            repeatDays: [0, 1, 2, 3, 4], // Monday-first indices: Пн–Пт
            name: "Работа",
            penaltyAmount: 50,
            theme: requestedTheme()
        )
    }

    /// A progressive-scale variant of the firing sample. Used by the
    /// `firing-progressive` screen so the snoozed-state progressive pill
    /// («N-й поспать ещё») and the growing charge ladder render for the e2e
    /// progressive-snooze test. Anchored to `Date()` for the same
    /// positive-countdown reason as `firingSampleAlarm()`.
    private static func progressiveFiringAlarm() -> Alarm {
        Alarm(
            time: Date(),
            repeatDays: [0, 1, 2, 3, 4], // Monday-first indices: Пн–Пт
            name: "Спортзал",
            penaltyAmount: 50,
            progressiveScale: true,
            theme: requestedTheme()
        )
    }

    /// The warning sheet shaped exactly as `StatisticsViewController` presents
    /// it — the tour must open the screen the way the app does, or it stops
    /// being evidence about the app. Internal so a test can assert the shape.
    static func makeAlarmOffWarningSheet() -> AlarmOffWarningViewController {
        let warning = AlarmOffWarningViewController()
        warning.modalPresentationStyle = .pageSheet
        if let sheet = warning.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.preferredCornerRadius = AppRadius.xl
        }
        return warning
    }

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

    private static func requestedBackendAvailability() -> AlarmBackendAvailability {
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

    private static func requestedTheme() -> AlarmTheme {
        switch value(after: "-uitour-theme") {
        case "ocean": return .ocean
        case "mountains": return .mountains
        case "forest": return .forest
        case "neon": return .neon
        case "abstract": return .abstract
        default: return .dawn
        }
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

    private static func seedAlarms() {
        let repo = AlarmRepository.shared
        guard ((try? repo.fetchAllChecked()) ?? []).isEmpty else { return }
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        repo.save(Alarm(
            time: at(7, 30), repeatDays: [0, 1, 2, 3, 4], name: "Работа", penaltyAmount: 50
        ))
        repo.save(Alarm(
            time: at(9, 0), repeatDays: [5, 6], name: "Спортзал и длинная пробежка по набережной",
            penaltyAmount: 100, progressiveScale: true, theme: .ocean
        ))
        repo.save(Alarm(
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

    private static func forceBalance(to target: Double) {
        let service = BalanceService.shared
        let delta = target - service.balance
        if delta > 0 {
            _ = service.topUp(amount: delta)
        } else if delta < 0 {
            _ = service.charge(amount: -delta, alarmID: nil)
        }
    }

    // MARK: - Argument parsing

    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: flag), args.count > idx + 1 else { return nil }
        return args[idx + 1]
    }
}
#endif
