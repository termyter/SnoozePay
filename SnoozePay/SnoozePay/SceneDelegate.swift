//
//  SceneDelegate.swift
//  SnoozePay
//

import os
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        // Apply saved theme preference. Apply to the window directly: it isn't
        // attached to `windowScene.windows` yet, so `applyToActiveWindowScene`
        // would skip it.
        ThemeService.shared.apply(to: window)

        #if DEBUG
        // Visual-audit hook: `-uitour <screen>` mounts the requested screen
        // directly, bypassing splash/onboarding (see UITourLauncher).
        if let tourScreen = UITourLauncher.requestedScreen {
            UITourLauncher.mount(tourScreen, in: window)
            window.makeKeyAndVisible()
            return
        }
        #endif

        // Always mount the branded Splash first — it owns the first ~200ms of
        // perceived launch and crossfades into whichever real root the user
        // state requires (Onboarding → Permissions → TabBar).
        let splash = SplashViewController()
        splash.onFinished = { [weak self] in
            self?.transitionToInitialRoot()
        }
        window.rootViewController = splash
        window.makeKeyAndVisible()
    }

    // MARK: - Root selection

    /// Decide which "real" root to present after the splash finishes.
    /// Order: Onboarding (if not completed) → Permissions (if not yet shown)
    /// → TabBar.
    private func transitionToInitialRoot() {
        guard let window = window else { return }
        let nextRoot = makeNextRootViewController()
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.rootViewController = nextRoot
        } completion: { _ in
            // Cold launch by an AlarmKit alarm tap: the firing screen was
            // deferred while only the splash existed (swapping the root would
            // tear a screen presented over the splash back down). Now the real
            // root is mounted, mount the deferred firing screen (#382).
            AlarmFiringPresenter.shared.flushPendingPresentation()
        }
    }

    /// Build the appropriate root VC for the current launch state. Extracted
    /// so the post-onboarding / post-permissions transitions can reuse the
    /// same selector without duplicating the precedence logic.
    private func makeNextRootViewController() -> UIViewController {
        if !OnboardingViewController.isCompleted {
            let onboarding = OnboardingViewController()
            onboarding.onFinished = { [weak self] in
                self?.transitionAfterOnboarding()
            }
            return onboarding
        }
        if !PermissionsViewController.hasBeenShown {
            return makePermissionsViewController()
        }
        return Self.makeMainTabBar()
    }

    private func makePermissionsViewController() -> UIViewController {
        let permissions = PermissionsViewController()
        permissions.onFinished = { [weak self] in
            self?.transitionToMainApp()
        }
        return permissions
    }

    // MARK: - Onboarding / Permissions transitions

    private func transitionAfterOnboarding() {
        guard let window = window else { return }
        // Onboarding finished — Permissions is the natural next step on a
        // fresh install. If for some reason the flag was already flipped
        // (e.g. test fixture), fall straight through to the tab bar.
        let nextRoot: UIViewController = PermissionsViewController.hasBeenShown
            ? Self.makeMainTabBar()
            : makePermissionsViewController()
        UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
            window.rootViewController = nextRoot
        }
    }

    private func transitionToMainApp() {
        guard let window = window else {
            // Permissions flow already flipped its "shown" flag — bailing out
            // here strands the user on a dead screen with no trace (#210).
            AppLogger.appDelegate.error("transitionToMainApp: window nil — user stuck on onboarding")
            return
        }
        let tabBar = Self.makeMainTabBar()
        UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
            window.rootViewController = tabBar
        }
    }

    // MARK: - Root UI setup

    /// Static so the DEBUG `UITourLauncher` can mount the same tab bar the
    /// production flow uses — duplicating the tab setup would let the audit
    /// build drift from what users actually see.
    static func makeMainTabBar() -> UIViewController {
        let tabBar = UITabBarController()

        // Alarms tab
        let alarmsVC = AlarmsListViewController()
        let alarmsNav = UINavigationController(rootViewController: alarmsVC)
        alarmsNav.tabBarItem = UITabBarItem(
            title: "Будильники",
            image: UIImage(systemName: "alarm"),
            selectedImage: UIImage(systemName: "alarm.fill")
        )

        // Wallet tab — replaces the legacy Settings tab per V2 design
        // (Settings moved behind a gear icon on Alarms / Wallet headers).
        let walletVC = WalletViewController()
        let walletNav = UINavigationController(rootViewController: walletVC)
        // Design-system wallet glyph (SPComponents.jsx `IconWallet`) — a
        // template image, so the appearance's icon colors tint it for both
        // states; no separate "filled" selected variant in the lucide set.
        let walletIcon = SPIcons.wallet(size: 24)
        walletNav.tabBarItem = UITabBarItem(
            title: "Кошелёк",
            image: walletIcon,
            selectedImage: walletIcon
        )

        // Statistics tab
        let statsVC = StatisticsViewController()
        let statsNav = UINavigationController(rootViewController: statsVC)
        statsNav.tabBarItem = UITabBarItem(
            title: "Статистика",
            image: UIImage(systemName: "chart.bar"),
            selectedImage: UIImage(systemName: "chart.bar.fill")
        )

        tabBar.viewControllers = [alarmsNav, walletNav, statsNav]
        applyTabBarStyle(to: tabBar.tabBar)
        return tabBar
    }

    /// V3 tab-bar chrome per `components.css` `.sp-tabbar`: bg1 at 85% over
    /// blur, stroke-1 top hairline, money-400 active tint / fg3 inactive,
    /// semibold 11pt labels, 28pt rounded top corners.
    private static func applyTabBarStyle(to tabBar: UITabBar) {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        // `bg1` is #0E1320 dark / #FFFFFF light — exactly the design's
        // rgba(14,19,32,.85) / rgba(255,255,255,.85) over blur(20px).
        // `withAlphaComponent` keeps the dynamic provider, so both modes stay
        // correct after trait changes.
        appearance.backgroundColor = AppColors.bg1.withAlphaComponent(0.85)
        // Top hairline (`border-top: 1px solid var(--sp-stroke-1)`) — UIKit
        // models the bar's top edge line as its "shadow".
        appearance.shadowColor = AppColors.stroke1

        let item = UITabBarItemAppearance()
        // `.sp-tabbar__label { font: 600 11px }` — semibold 11pt.
        let labelFont = AppFonts.sans(.semibold, 11)
        item.normal.iconColor = AppColors.fg3
        item.normal.titleTextAttributes = [
            .font: labelFont,
            .foregroundColor: AppColors.fg3
        ]
        item.selected.iconColor = AppColors.money400
        item.selected.titleTextAttributes = [
            .font: labelFont,
            .foregroundColor: AppColors.money400
        ]
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        tabBar.standardAppearance = appearance
        // Same chrome when content scrolls underneath and at rest — the
        // design's bar is always translucent-over-blur, never transparent.
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = AppColors.money400
        tabBar.unselectedItemTintColor = AppColors.fg3

        // `border-radius: 28px 28px 0 0`. UITabBar has no native corner API;
        // masking the bar's own layer is the lightest faithful approach. The
        // bar's frame already extends through the bottom safe area, so
        // clipping only the *top* corners doesn't fight the home-indicator
        // extension or the blur background.
        tabBar.layer.cornerRadius = AppRadius.xl
        tabBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        tabBar.layer.masksToBounds = true
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Flush any AlarmKit firing screen deferred while the scene wasn't yet
        // active (#382): tapping an AlarmKit alarm button runs the intent before
        // the window exists, so `AlarmFiringPresenter` records the alarm as
        // pending and mounts it here once a root view controller is attached.
        AlarmFiringPresenter.shared.flushPendingPresentation()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // UserDefaults writes are synchronous — no explicit save needed
    }
}
