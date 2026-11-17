import UIKit
import XCTest
@testable import SnoozePay

/// The theme picker's tile must draw what it promises (#1110).
///
/// **Badge.** The selected tile's 22pt money-gradient circle was a
/// `CAGradientLayer` sublayer of the badge view, framed from the *cell's*
/// `layoutSubviews`. The badge is three levels down (cell → contentView →
/// card → badge); when the cell's callback runs, Auto Layout has pushed
/// geometry one level only, so the badge's bounds are still `.zero` and the
/// layer stays 0×0. Only the bare `fgOnMoney` tick shows — dark ink on a dark
/// tile in the dark theme. Same class as #553 (`PermissionCardIconTileTests`).
///
/// **Custom slot.** The empty «Своё фото» tile painted white copy on a dimmed
/// light-grey gradient in the light theme. Contrast is read off the *rendered*
/// tile behind each label, not off token pairs, so it measures what the user
/// sees whatever the fill is made of.
///
/// One layout pass only: a second pass hands the sublayer a size it never
/// receives in the app and would turn the badge test green against the defect.
final class AlarmThemeTileCellTests: XCTestCase {

    private let textFloor: CGFloat = 4.5
    private let badgeSide: CGFloat = 22

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - Badge

    func testSelectedBadge_gradientFillsTheBadge_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let cell = makeHostedCell(style: style) {
                $0.configure(theme: .dawn, isCustomSlot: false, isSelected: true, customImage: nil)
            }
            let badge = try XCTUnwrap(badgeView(in: cell), "no visible 22pt badge in \(style.name)")
            XCTAssertEqual(badge.bounds.size, CGSize(width: badgeSide, height: badgeSide))

            let gradient = try XCTUnwrap(gradientLayer(of: badge), "badge owns no gradient in \(style.name)")
            let rect = gradient === badge.layer ? badge.bounds : badge.layer.convert(gradient.bounds, from: gradient)
            XCTAssertEqual(
                rect.size, badge.bounds.size,
                "the badge gradient is \(rect.size) inside a \(badge.bounds.size) badge in \(style.name) — "
                    + "nothing is painted behind the tick"
            )

            let stops = try XCTUnwrap(gradient.colors as? [CGColor], "badge gradient has no stops")
            // Resolved from the tokens, not through `SPSupport`, so the test does
            // not inherit a bug in the helper it is checking.
            let theme = UITraitCollection(userInterfaceStyle: style)
            let expected = [AppColors.money400, AppColors.money500, AppColors.money700]
                .map { $0.resolvedColor(with: theme) }
            XCTAssertEqual(stops.count, expected.count)
            for (actual, wanted) in zip(stops, expected) {
                XCTAssertEqual(
                    UIColor(cgColor: actual).hexText, wanted.hexText,
                    "badge stops are not the \(style.name) money ramp"
                )
            }
        }
    }

    // MARK: - Custom slot copy

    func testCustomSlotLabels_clearTextContrastOnTheRenderedTile_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let cell = makeHostedCell(style: style) {
                $0.configure(theme: .dawn, isCustomSlot: true, isSelected: false, customImage: nil)
            }
            let labels = visibleLabels(in: cell)
            XCTAssertEqual(labels.count, 2, "expected title + subtitle on the custom tile")

            labels.forEach { $0.isHidden = true }
            let tile = render(cell)
            labels.forEach { $0.isHidden = false }

            for label in labels {
                let ink = label.textColor.resolvedColor(with: label.traitCollection)
                let rect = label.convert(label.bounds, to: cell)
                let worst = samplePoints(in: rect)
                    .map { contrast(composite(ink, over: tile.color(at: $0)), tile.color(at: $0)) }
                    .min() ?? 0
                XCTAssertGreaterThanOrEqual(
                    worst, textFloor,
                    "«\(label.text ?? "")» reads \(String(format: "%.2f", worst)):1 on the \(style.name) custom tile"
                )
            }
        }
    }

    // MARK: - Reuse

    /// One cell walked through the states the grid recycles it between.
    ///
    /// Light theme on purpose: `bg1` is white there, so "the tile centre is
    /// not `bg1`" cleanly means "a preview or photo is painted" — in dark the
    /// dawn gradient is too close to `bg1 #0E1320` to tell apart. Each step
    /// must undo the previous one: the photo hides the preview, the empty
    /// custom slot swaps the copy ink, only the selected step shows the badge.
    /// On the pre-#1110 cell this fails at the empty-custom ink and the badge
    /// fill; photo → built-in already held, because
    /// `SPThemePreviewView.apply(theme:)` un-hides itself.
    func testReusedCell_restoresEachStateFromThePreviousOne() throws {
        let style = UIUserInterfaceStyle.light
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let cell = makeHostedCell(style: style) {
            $0.configure(theme: .dawn, isCustomSlot: true, isSelected: false, customImage: photo)
        }
        let theme = cell.traitCollection
        let pageHex = AppColors.bg1.resolvedColor(with: theme).hexText
        let white = UIColor.white.hexText
        let ink = AppColors.fg1.resolvedColor(with: theme).hexText

        let steps = [
            Step(name: "photo", apply: { _ in }, paintsPreview: true, titleHex: white, selected: false),
            Step(name: "built-in dawn", apply: {
                $0.configure(theme: .dawn, isCustomSlot: false, isSelected: false, customImage: nil)
            }, paintsPreview: true, titleHex: white, selected: false),
            Step(name: "empty custom", apply: {
                $0.configure(theme: .dawn, isCustomSlot: true, isSelected: false, customImage: nil)
            }, paintsPreview: false, titleHex: ink, selected: false),
            Step(name: "built-in selected", apply: {
                $0.configure(theme: .dawn, isCustomSlot: false, isSelected: true, customImage: nil)
            }, paintsPreview: true, titleHex: white, selected: true)
        ]

        for step in steps {
            step.apply(cell)
            cell.window?.setNeedsLayout()
            cell.window?.layoutIfNeeded()
            let tile = render(cell)

            let centre = tile.color(at: CGPoint(x: cell.bounds.midX, y: cell.bounds.midY)).hexText
            if step.paintsPreview {
                XCTAssertNotEqual(centre, pageHex, "\(step.name): the tile centre is bare `bg1` — nothing painted")
            }

            let title = try XCTUnwrap(visibleLabels(in: cell).first, "\(step.name): no title label")
            XCTAssertEqual(
                title.textColor.resolvedColor(with: title.traitCollection).hexText, step.titleHex,
                "\(step.name): wrong title ink"
            )

            let badge = badgeView(in: cell)
            XCTAssertEqual(badge != nil, step.selected, "\(step.name): badge visibility")
            if let badge {
                // Inside the circle, clear of the tick: the money ramp is green-dominant.
                let edge = tile.color(at: badge.convert(CGPoint(x: 4, y: badge.bounds.midY), to: cell))
                let parts = channels(edge)
                XCTAssertTrue(parts[1] > parts[0] && parts[1] > parts[2], "\(step.name): badge not painted green")
            }
        }
    }

    // MARK: - Harness

    private func makeHostedCell(
        style: UIUserInterfaceStyle,
        configure: (AlarmThemeTileCell) -> Void
    ) -> AlarmThemeTileCell {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        hostWindows.append(window)
        window.isHidden = false
        let container = UIView(frame: window.bounds)
        container.backgroundColor = AppColors.bg0
        window.addSubview(container)
        container.traitOverrides.userInterfaceStyle = style
        container.updateTraitsIfNeeded()

        let cell = AlarmThemeTileCell(frame: CGRect(x: 20, y: 100, width: 110, height: 132))
        container.addSubview(cell)
        cell.updateTraitsIfNeeded()
        configure(cell)

        window.setNeedsLayout()
        window.layoutIfNeeded()
        XCTAssertEqual(cell.traitCollection.userInterfaceStyle, style, "harness lost the theme override")
        return cell
    }

    /// Found by shape (22pt, rounded, hosts the tick) so a rename survives.
    private func badgeView(in root: UIView) -> UIView? {
        var queue = root.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if !view.isHidden, view.layer.cornerRadius > 0,
               view.subviews.count == 1, view.subviews.first is UIImageView,
               view.bounds.width <= badgeSide + 0.5 {
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

    private func visibleLabels(in root: UIView) -> [UILabel] {
        var result: [UILabel] = []
        var queue = root.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let label = view as? UILabel, !label.isHidden, !(label.text ?? "").isEmpty {
                result.append(label)
            }
            queue.append(contentsOf: view.subviews)
        }
        return result
    }

    private func samplePoints(in rect: CGRect) -> [CGPoint] {
        let columns = 6, rows = 3
        return (0..<columns).flatMap { col in
            (0..<rows).map { row in
                CGPoint(
                    x: rect.minX + rect.width * (CGFloat(col) + 0.5) / CGFloat(columns),
                    y: rect.minY + rect.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                )
            }
        }
    }

    private func render(_ view: UIView) -> RenderedTile {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            // The page behind the tile, so translucent fills composite on it.
            AppColors.bg0.resolvedColor(with: view.traitCollection).setFill()
            context.fill(view.bounds)
            view.layer.render(in: context.cgContext)
        }
        return RenderedTile(image: image)
    }

    // MARK: - Colour maths

    private func composite(_ top: UIColor, over bottom: UIColor) -> UIColor {
        let ink = channels(top)
        let page = channels(bottom)
        let mix = (0..<3).map { ink[$0] * ink[3] + page[$0] * (1 - ink[3]) }
        return UIColor(red: mix[0], green: mix[1], blue: mix[2], alpha: 1)
    }

    private func channels(_ color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func value(_ raw: CGFloat) -> CGFloat {
            raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * value(red) + 0.7152 * value(green) + 0.0722 * value(blue)
    }

    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = luminance(lhs)
        let second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

/// One configuration in the reuse walk and what it must render.
private struct Step {
    let name: String
    let apply: (AlarmThemeTileCell) -> Void
    let paintsPreview: Bool
    let titleHex: String
    let selected: Bool
}

/// Pixel reader over a 1x RGBA8 sRGB copy of the rendered tile.
private struct RenderedTile {
    private let width: Int
    private let height: Int
    private let bytes: [UInt8]

    init(image: UIImage) {
        let cgImage = image.cgImage
        let width = cgImage?.width ?? 0
        let height = cgImage?.height ?? 0
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        if let cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) {
            buffer.withUnsafeMutableBytes { raw in
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        self.width = width
        self.height = height
        bytes = buffer
    }

    func color(at point: CGPoint) -> UIColor {
        let col = min(max(Int(point.x), 0), max(width - 1, 0))
        let row = min(max(Int(point.y), 0), max(height - 1, 0))
        let index = (row * width + col) * 4
        guard index + 3 < bytes.count else { return .black }
        return UIColor(
            red: CGFloat(bytes[index]) / 255,
            green: CGFloat(bytes[index + 1]) / 255,
            blue: CGFloat(bytes[index + 2]) / 255,
            alpha: 1
        )
    }
}

private extension UIColor {
    var hexText: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}

private extension UIUserInterfaceStyle {
    var name: String { self == .light ? "light" : "dark" }
}
