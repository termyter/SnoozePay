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
        return makeTabBarController()
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
            ? makeTabBarController()
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
        let tabBar = makeTabBarController()
        UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
            window.rootViewController = tabBar
        }
    }

    // MARK: - Root UI setup

    private func makeTabBarController() -> UIViewController {
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
        walletNav.tabBarItem = UITabBarItem(
            title: "Кошелёк",
            image: UIImage(systemName: "creditcard"),
            selectedImage: UIImage(systemName: "creditcard.fill")
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
        return tabBar
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // UserDefaults writes are synchronous — no explicit save needed
    }
}
