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
///   `-uitour-seed`           seed demo alarms / transactions / wake history
///   `-uitour-balance <n>`    force balance to exactly n ₽ (via service APIs)
///   `-uitour-theme <id>`     firing-screen theme: dawn|ocean|mountains|forest|neon|abstract
///
/// Supported screens: onboarding, permissions, alarms, wallet, stats,
/// settings, create, edit, theme-picker, sound-picker, volume-picker,
/// confirm-delete, firing, firing-snoozed, firing-nobalance, firing-topup,
/// txhistory, periodpicker, deposit, streak.
enum UITourLauncher {

    static var requestedScreen: String? { value(after: "-uitour") }

    // MARK: - Mounting

    static func mount(_ screen: String, in window: UIWindow) {
        seedIfRequested()

        switch screen {
        case "onboarding":
            window.rootViewController = OnboardingViewController()
        case "permissions":
            window.rootViewController = PermissionsViewController()
        case "alarms":
            window.rootViewController = tabBar(selected: 0)
        case "wallet":
            window.rootViewController = tabBar(selected: 1)
        case "stats":
            window.rootViewController = tabBar(selected: 2)
        case "settings":
            mountPushed(SettingsViewController(), onTab: 0, in: window)
        case "create":
            mountPresented(createNav(alarm: nil), onTab: 0, in: window)
        case "edit":
            mountPresented(createNav(alarm: sampleAlarm()), onTab: 0, in: window)
        case "theme-picker":
            mountPushedOnCreate(in: window) { vm in
                AlarmThemePickerViewController(currentTheme: vm, onSelect: { _ in })
            }
        case "sound-picker":
            mountPushedOnCreate(in: window) { _ in
                SoundPickerViewController(
                    sounds: CreateAlarmViewModel(alarm: nil).availableSounds,
                    selectedID: "radar",
                    onSelect: { _ in },
                    previewSound: { _ in }
                )
            }
        case "volume-picker":
            mountPushedOnCreate(in: window) { _ in
                VolumePickerViewController(volume: 0.7, fadeIn: true)
            }
        case "confirm-delete":
            let nav = createNav(alarm: sampleAlarm())
            mountPresented(nav, onTab: 0, in: window)
            presentLater(ConfirmDeleteAlarmViewController(), over: nav)
        case "firing":
            window.rootViewController = AlarmFiringViewController(alarm: sampleAlarm())
        case "firing-snoozed":
            window.rootViewController = AlarmFiringViewController(alarm: sampleAlarm(), snoozeCount: 2)
        case "firing-nobalance":
            forceBalance(to: 0)
            window.rootViewController = AlarmFiringViewController(alarm: sampleAlarm())
        case "firing-topup":
            let firing = AlarmFiringViewController(alarm: sampleAlarm())
            window.rootViewController = firing
            presentLater(FiringTopUpBottomSheetViewController(), over: firing)
        case "txhistory":
            mountPushed(WalletTransactionHistoryViewController(), onTab: 1, in: window)
        case "periodpicker":
            let history = WalletTransactionHistoryViewController()
            mountPushed(history, onTab: 1, in: window)
            presentLater(
                PeriodPickerSheetViewController(selected: nil, years: [2025, 2026], onApply: { _ in }),
                over: history
            )
        case "deposit":
            let root = tabBar(selected: 1)
            window.rootViewController = root
            presentLater(DepositBottomSheetViewController(), over: root)
        case "streak":
            let root = tabBar(selected: 2)
            window.rootViewController = root
            presentLater(StreakModalViewController(streakDays: 7), over: root)
        default:
            // Unknown screen id — land on the alarms tab so the audit
            // screenshot makes the mistake obvious instead of hanging.
            window.rootViewController = tabBar(selected: 0)
        }
    }

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
        let nav = UINavigationController(rootViewController: CreateAlarmViewController(alarm: alarm))
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
        guard repo.fetchAll().isEmpty else { return }
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
        guard repo.fetchAll().isEmpty else { return }
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
        for daysAgo in 0...45 where daysAgo % 3 != 1 {
            if let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) {
                store.recordWake(on: date)
            }
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
