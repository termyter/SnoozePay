import UIKit
import XCTest
@testable import SnoozePay

/// TEMPORARY — #553 diagnostic, deleted in the same PR that carries the fix.
///
/// Round 1 (run 33253066702) proved the *harness* was the first defect: with a
/// controller as the window's `rootViewController`, nothing laid out at all
/// (card frame `.zero`) and `overrideUserInterfaceStyle` never propagated, so
/// every geometry test skipped itself and the suite reported green. The same
/// is true of `StreakModalFlameBadgeTests` from #516 — three of its four cases
/// skip on every run.
///
/// Round 2 tries five mounting strategies and prints, for each, whether the
/// card got a size and whether the requested theme reached it. Then it prints
/// the #553 measurements from whichever strategy works.
final class PermissionCardIconTileDiagnosticTests: XCTestCase {

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.rootViewController = nil }
        hostWindows = []
        super.tearDown()
    }

    func testDiagnostic_findAHarnessThatActuallyLaysOut() {
        for (name, build) in strategies {
            let card = build(.dark, .granted)
            let host = iconHostView(of: card)
            let gradient = host.flatMap(gradientLayer(of:))
            print("""
            DIAG553-H [\(name)] \
            card.frame=\(card.frame) \
            host.bounds=\(host?.bounds.debugDescription ?? "NO HOST") \
            gradient.frame=\(gradient.map { "\($0.frame)" } ?? "n/a") \
            card.trait=\(styleName(card.traitCollection.userInterfaceStyle)) \
            host.trait=\(host.map { styleName($0.traitCollection.userInterfaceStyle) } ?? "n/a")
            """)
        }
    }

    func testDiagnostic_dumpIconTileGeometryAndStops() {
        let statuses: [(PermissionStatus, String)] = [
            (.granted, "granted"),
            (.enabled, "enabled"),
            (.actionable, "actionable"),
            (.unavailable, "unavailable")
        ]
        for (name, build) in strategies where name.hasPrefix("C") || name.hasPrefix("D") {
            for style in [UIUserInterfaceStyle.dark, .light] {
                for (status, statusName) in statuses {
                    let card = build(style, status)
                    guard let host = iconHostView(of: card) else { continue }
                    let gradient = gradientLayer(of: host)
                    let stops = (gradient?.colors as? [CGColor] ?? [])
                        .map { String(format: "#%06X", hex(UIColor(cgColor: $0))) }
                    let glyph = host.subviews.compactMap { $0 as? UIImageView }.first
                    print("""
                    DIAG553-G [\(name)/\(styleName(style))/\(statusName)] \
                    host.bounds=\(host.bounds) \
                    host.bg=\(describe(host.backgroundColor, host.traitCollection)) \
                    gradient.frame=\(gradient.map { "\($0.frame)" } ?? "ABSENT") \
                    gradient.isHidden=\(gradient.map { "\($0.isHidden)" } ?? "n/a") \
                    gradient.colors=\(stops) \
                    glyph.frame=\(glyph.map { "\($0.frame)" } ?? "n/a") \
                    glyph.tint=\(describe(glyph?.tintColor, host.traitCollection))
                    """)
                }
            }
        }
    }

    // MARK: - Mounting strategies

    private typealias Build = (UIUserInterfaceStyle, PermissionStatus) -> PermissionCardView

    private var strategies: [(String, Build)] {
        [
            ("A-rootVC-vcOverride", { [self] style, status in
                let window = makeWindow()
                let controller = UIViewController()
                controller.overrideUserInterfaceStyle = style
                window.rootViewController = controller
                controller.loadViewIfNeeded()
                controller.view.frame = window.bounds
                let card = install(in: controller.view, status: status)
                window.setNeedsLayout()
                window.layoutIfNeeded()
                return card
            }),
            ("B-windowSubview-containerOverride", { [self] style, status in
                let window = makeWindow()
                let container = UIView(frame: window.bounds)
                container.overrideUserInterfaceStyle = style
                window.addSubview(container)
                let card = install(in: container, status: status)
                window.setNeedsLayout()
                window.layoutIfNeeded()
                return card
            }),
            ("C-windowSubview-cardOverride", { [self] style, status in
                let window = makeWindow()
                let container = UIView(frame: window.bounds)
                window.addSubview(container)
                let card = install(in: container, status: status, override: style)
                container.setNeedsLayout()
                container.layoutIfNeeded()
                return card
            }),
            ("D-detachedContainer-cardOverride", { [self] style, status in
                let container = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
                let card = install(in: container, status: status, override: style)
                container.setNeedsLayout()
                container.layoutIfNeeded()
                return card
            }),
            ("E-rootVC-visible", { [self] style, status in
                let window = makeWindow()
                let controller = UIViewController()
                controller.overrideUserInterfaceStyle = style
                window.rootViewController = controller
                window.isHidden = false
                controller.loadViewIfNeeded()
                controller.view.frame = window.bounds
                let card = install(in: controller.view, status: status)
                window.setNeedsLayout()
                window.layoutIfNeeded()
                return card
            })
        ]
    }

    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        hostWindows.append(window)
        return window
    }

    private func install(
        in container: UIView,
        status: PermissionStatus,
        override: UIUserInterfaceStyle? = nil
    ) -> PermissionCardView {
        container.backgroundColor = AppColors.bg0
        let card = PermissionCardView(kind: .notifications)
        if let override { card.overrideUserInterfaceStyle = override }
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 100)
        ])
        card.apply(status: status)
        return card
    }

    // MARK: - Readers

    private func iconHostView(of card: PermissionCardView) -> UIView? {
        var queue: [UIView] = card.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            let hasGlyph = view.subviews.contains { $0 is UIImageView }
            if hasGlyph, view.subviews.count == 1, view.layer.cornerRadius > 0 {
                return view
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    private func gradientLayer(of view: UIView) -> CAGradientLayer? {
        if let own = view.layer as? CAGradientLayer { return own }
        return view.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
    }

    private func styleName(_ style: UIUserInterfaceStyle) -> String {
        switch style {
        case .light: return "light"
        case .dark: return "dark"
        default: return "unspecified"
        }
    }

    private func describe(_ color: UIColor?, _ trait: UITraitCollection) -> String {
        guard let color else { return "nil" }
        let resolved = color.resolvedColor(with: trait)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%06X@%.2f", hex(resolved), alpha)
    }

    private func hex(_ color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
        let toByte: (CGFloat) -> UInt32 = { UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255)) }
        return (toByte(red) << 16) | (toByte(green) << 8) | toByte(blue)
    }
}
