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
///   `-uitour-theme <id>`     firing-screen theme: dawn|ocean|mountains|forest|neon|abstract
///
/// Supported screens: onboarding, permissions, alarms, wallet, stats,
/// settings, create, edit, theme-picker, sound-picker, volume-picker,
/// confirm-delete, firing, firing-snoozed, firing-progressive,
/// firing-nobalance, firing-topup,
/// txhistory, periodpicker, deposit, streak.
enum UITourLauncher {

    static var requestedScreen: String? { value(after: "-uitour") }

    // MARK: - Mounting

    static func mount(_ screen: String, in window: UIWindow) {
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
            mountPresented(nav, onTab: 0, in: window)
            presentLater(ConfirmDeleteAlarmViewController(), over: nav)
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

    private static func mountPresented(_ vc: UIViewController, onTab index: Int, in window: UIWindow) {
        let root = tabBar(selected: index)
        window.rootViewController = root
        presentLater(vc, over: root)
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
        mountPresented(nav, onTab: 0, in: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            nav.pushViewController(makePicker(.dawn), animated: false)
        }
    }

    /// Presents a sheet/modal after the root has had a beat to lay out —
    /// presenting from a VC that isn't in the hierarchy yet is a no-op.
    private static func presentLater(_ vc: UIViewController, over presenter: UIViewController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            (presenter.presentedViewController ?? presenter).present(vc, animated: false)
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
