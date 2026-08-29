import UIKit
import XCTest
@testable import SnoozePay

/// TEMPORARY — #553 diagnostic, deleted in the same PR that carries the fix.
///
/// The issue names two plausible causes for the missing money tile and says to
/// measure rather than guess: empty/frozen stops (a `UITraitCollection.current`
/// read in a stored-property initializer) versus a zero-frame sublayer. This
/// mounts a real card in a window, runs one layout pass, and prints
/// `colors` / `frame` / `isHidden` / host bounds for every status in both
/// themes so the fix targets the cause that is actually there.
final class PermissionCardIconTileDiagnosticTests: XCTestCase {

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.rootViewController = nil }
        hostWindows = []
        super.tearDown()
    }

    func testDiagnostic_dumpIconTileGeometryAndStops() throws {
        let statuses: [(PermissionStatus, String)] = [
            (.granted, "granted"),
            (.enabled, "enabled"),
            (.actionable, "actionable"),
            (.unavailable, "unavailable")
        ]
        for style in [UIUserInterfaceStyle.dark, .light] {
            for (status, statusName) in statuses {
                let card = makeHostedCard(status: status, style: style)
                let host = try XCTUnwrap(iconHostView(of: card), "no icon host found")
                let gradient = host.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
                    ?? (host.layer as? CAGradientLayer)
                let stops = (gradient?.colors as? [CGColor] ?? []).map { hex(UIColor(cgColor: $0)) }
                let glyph = host.subviews.compactMap { $0 as? UIImageView }.first
                print("""
                DIAG553 [\(style == .light ? "light" : "dark")/\(statusName)] \
                cardFrame=\(card.frame) \
                iconHost.bounds=\(host.bounds) \
                iconHost.bg=\(describe(host.backgroundColor, host.traitCollection)) \
                gradient=\(gradient == nil ? "ABSENT" : "present") \
                gradient.frame=\(gradient.map { "\($0.frame)" } ?? "n/a") \
                gradient.isHidden=\(gradient.map { "\($0.isHidden)" } ?? "n/a") \
                gradient.colors=\(stops) \
                glyph.frame=\(glyph.map { "\($0.frame)" } ?? "n/a") \
                glyph.tint=\(describe(glyph?.tintColor, host.traitCollection))
                """)
            }
        }
    }

    // MARK: - Fixtures

    private func makeHostedCard(status: PermissionStatus, style: UIUserInterfaceStyle) -> PermissionCardView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let controller = UIViewController()
        controller.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        hostWindows.append(window)

        controller.loadViewIfNeeded()
        controller.view.backgroundColor = AppColors.bg0
        let card = PermissionCardView(kind: .notifications)
        controller.view.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 100)
        ])
        card.apply(status: status)

        controller.view.frame = window.bounds
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return card
    }

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
