#if DEBUG
import UIKit

/// The `-uitour <screen>` route table: screen id → how that screen is built and
/// shown. Split out of `UITourLauncher` (#564), which kept the *mechanics* —
/// argument parsing, seeding, the root-view-controller swap — while this file
/// answers only "what does this name open".
///
/// Route names are a contract, not an implementation detail: `/audit`,
/// `audit-design`, `ui-explorer`, `qa-tester` and the `SnoozePayUITests` suite
/// all pass them as launch arguments. Renaming one does not fail a build — the
/// app just lands on the alarms tab and the audit screenshots a plausible but
/// wrong screen. `UITourRouteRegistryTests` pins the list for that reason.
///
/// Supported screens: onboarding, permissions, alarms, alarms-nobackend,
/// wallet, stats, settings, create, edit, theme-picker, sound-picker,
/// volume-picker, confirm-delete, firing, firing-snoozed, firing-progressive,
/// firing-nobalance, firing-topup, alarm-off-warning, txhistory, periodpicker,
/// deposit, streak.
enum UITourRoutes {

    /// The mounter for `screen`, or the fallback. An unknown screen id lands on
    /// the alarms tab so the audit screenshot makes the mistake obvious
    /// instead of hanging.
    static func mounter(for screen: String) -> (UIWindow) -> Void {
        mounters[screen] ?? { $0.rootViewController = tabBar(selected: 0) }
    }

    /// Screen-id → mounter registry. A flat dictionary (instead of a switch)
    /// keeps `mount` trivially simple for the linter and makes the supported
    /// screen list greppable — and assertable — in one place.
    static let mounters: [String: (UIWindow) -> Void] = [
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
            AlarmBackendMonitor.uiTourForcedAvailability = UITourLauncher.requestedBackendAvailability()
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
            // Sequence, don't race (#467): both presentations used to share
            // one 0.8 s deadline, so the sheet asked a navigation controller
            // still mid-transition to present — a silent no-op. Chaining off
            // the form's completion guarantees the presenter is in the window.
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
            UITourLauncher.forceBalance(to: 0)
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
        // Same chaining as `confirm-delete`: one timer, then a completion (#467).
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

    // MARK: - Sample data

    private static func sampleAlarm() -> Alarm {
        Alarm(
            time: Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date(),
            repeatDays: [0, 1, 2, 3, 4], // Monday-first indices: Пн–Пт
            name: "Работа",
            penaltyAmount: 50,
            theme: UITourLauncher.requestedTheme()
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
            theme: UITourLauncher.requestedTheme()
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
            theme: UITourLauncher.requestedTheme()
        )
    }
}
#endif
