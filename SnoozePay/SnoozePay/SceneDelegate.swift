//
//  SceneDelegate.swift
//  SnoozePay
//

import UIKit
import os

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

        if OnboardingViewController.isCompleted {
            window.rootViewController = makeRootViewController()
        } else {
            let onboarding = OnboardingViewController()
            onboarding.onFinished = { [weak self] in
                self?.transitionToMainApp()
            }
            window.rootViewController = onboarding
        }

        window.makeKeyAndVisible()
    }

    // MARK: - Onboarding transition

    private func transitionToMainApp() {
        guard let window = window else {
            AppLogger.appDelegate.error(
                "transitionToMainApp: window is nil — onboarding ack was set but the user is stuck on the old root"
            )
            return
        }
        let tabBar = makeRootViewController()
        UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
            window.rootViewController = tabBar
        }
    }

    // MARK: - Root UI setup

    private func makeRootViewController() -> UIViewController {
        let tabBar = UITabBarController()

        // Alarms tab
        let alarmsVC = AlarmsListViewController()
        let alarmsNav = UINavigationController(rootViewController: alarmsVC)
        alarmsNav.tabBarItem = UITabBarItem(
            title: "Будильники",
            image: UIImage(systemName: "alarm"),
            selectedImage: UIImage(systemName: "alarm.fill")
        )

        // Statistics tab
        let statsVC = StatisticsViewController()
        let statsNav = UINavigationController(rootViewController: statsVC)
        statsNav.tabBarItem = UITabBarItem(
            title: "Статистика",
            image: UIImage(systemName: "chart.bar"),
            selectedImage: UIImage(systemName: "chart.bar.fill")
        )

        // Settings tab
        let settingsVC = SettingsViewController()
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        settingsNav.tabBarItem = UITabBarItem(
            title: "Настройки",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        tabBar.viewControllers = [alarmsNav, statsNav, settingsNav]
        return tabBar
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // UserDefaults writes are synchronous — no explicit save needed
    }
}
