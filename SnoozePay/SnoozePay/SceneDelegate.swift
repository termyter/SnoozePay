//
//  SceneDelegate.swift
//  SnoozePay
//

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

        // Apply saved theme preference
        let savedTheme = UserDefaults.standard.string(forKey: "preferred_theme") ?? "system"
        switch savedTheme {
        case "dark": window.overrideUserInterfaceStyle = .dark
        case "light": window.overrideUserInterfaceStyle = .light
        default: window.overrideUserInterfaceStyle = .unspecified
        }

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
        guard let window = window else { return }
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
