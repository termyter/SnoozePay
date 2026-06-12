import UIKit

/// Code-drawn design-system icons — the Swift port of the `Ico` SVG set in
/// `docs/design/v2-handoff/components/SPComponents.jsx` (L345+).
///
/// Recipe (matches the JSX wrapper): 24×24 viewBox, 1.75 stroke, round caps
/// and joins, no fill, `currentColor` ink. Here that maps to a stroked
/// `UIBezierPath` rendered into a template `UIImage`, so `tintColor` plays
/// the role of `currentColor` — drop the image into any `UIImageView` /
/// `SPPill` and tint as usual.
///
/// Paths are authored in the 24-unit grid straight from the SVG `d`
/// attributes and scaled at render time; the stroke width scales with the
/// icon size exactly like an SVG `strokeWidth` would.
enum SPIcons {

    /// Монета с ₽ — circle + rouble glyph. The unified icon for money /
    /// balance / price indicators (replaces the abstract coin).
    /// JSX: `IconCoin` / `IconRubleCoin` (identical paths).
    static func coin(size: CGFloat) -> UIImage {
        render(size: size) { path in
            path.append(circle(center: CGPoint(x: 12, y: 12), radius: 9))
            path.append(rubleGlyph())
        }
    }

    /// Alias for `coin` — the JSX exports both names; chips reference
    /// `IconRubleCoin`, balance pills reference `IconCoin`.
    static func rubleCoin(size: CGFloat) -> UIImage {
        coin(size: size)
    }

    /// Та же монета, перечёркнутая диагональным слэшем — «нет денег».
    /// JSX: `IconCoinOff`.
    static func coinOff(size: CGFloat) -> UIImage {
        render(size: size) { path in
            path.append(circle(center: CGPoint(x: 12, y: 12), radius: 9))
            path.append(rubleGlyph())
            path.move(to: CGPoint(x: 4.5, y: 4.5))
            path.addLine(to: CGPoint(x: 19.5, y: 19.5))
        }
    }

    /// Тренд вверх — растущая ломаная со стрелкой. Reads as
    /// «увеличение/множитель» (progressive penalty). JSX: `IconTrendUp`.
    static func trendUp(size: CGFloat) -> UIImage {
        render(size: size) { path in
            path.move(to: CGPoint(x: 3, y: 17))
            path.addLine(to: CGPoint(x: 9, y: 11))
            path.addLine(to: CGPoint(x: 13, y: 15))
            path.addLine(to: CGPoint(x: 21, y: 7))
            path.move(to: CGPoint(x: 15, y: 7))
            path.addLine(to: CGPoint(x: 21, y: 7))
            path.addLine(to: CGPoint(x: 21, y: 13))
        }
    }

    /// Купюра с ₽ — rounded rect + rouble glyph. JSX: `IconBanknote`.
    static func banknote(size: CGFloat) -> UIImage {
        render(size: size) { path in
            path.append(UIBezierPath(
                roundedRect: CGRect(x: 3, y: 7, width: 18, height: 10),
                cornerRadius: 2
            ))
            // Compact ₽: stem, half-circle bowl, crossbar.
            path.move(to: CGPoint(x: 10, y: 10))
            path.addLine(to: CGPoint(x: 10, y: 16))
            path.move(to: CGPoint(x: 10, y: 10))
            path.addLine(to: CGPoint(x: 12.2, y: 10))
            path.addArc(
                withCenter: CGPoint(x: 12.2, y: 11.6),
                radius: 1.6,
                startAngle: -.pi / 2,
                endAngle: .pi / 2,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: 10, y: 13.2))
            path.move(to: CGPoint(x: 8.6, y: 13.6))
            path.addLine(to: CGPoint(x: 12, y: 13.6))
        }
    }

    /// Кошелёк — body rect + fold line + card slot + top flap. The tab-bar
    /// glyph for the «Кошелёк» tab. JSX: `IconWallet`.
    static func wallet(size: CGFloat) -> UIImage {
        render(size: size) { path in
            // Body: `rect x=3 y=6 w=18 h=14 rx=3`.
            path.append(UIBezierPath(
                roundedRect: CGRect(x: 3, y: 6, width: 18, height: 14),
                cornerRadius: 3
            ))
            // Fold line + card slot: `M3 10h18` / `M16 14h2`.
            path.move(to: CGPoint(x: 3, y: 10))
            path.addLine(to: CGPoint(x: 21, y: 10))
            path.move(to: CGPoint(x: 16, y: 14))
            path.addLine(to: CGPoint(x: 18, y: 14))
            // Top flap: `M18 6V4a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v2`.
            path.move(to: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 4))
            path.addArc(
                withCenter: CGPoint(x: 16, y: 4),
                radius: 2,
                startAngle: 0,
                endAngle: -.pi / 2,
                clockwise: false
            )
            path.addLine(to: CGPoint(x: 7, y: 2))
            path.addArc(
                withCenter: CGPoint(x: 7, y: 4),
                radius: 2,
                startAngle: -.pi / 2,
                endAngle: -.pi,
                clockwise: false
            )
            path.addLine(to: CGPoint(x: 5, y: 6))
        }
    }

    /// Колокольчик — купол + язычок + основание. The empty-state /
    /// notification glyph. JSX: `IconBell`
    /// (`M6 19V11a6 6 0 0 1 12 0v8` / `M4 19h16` / `M10 22h4`).
    static func bell(size: CGFloat) -> UIImage {
        render(size: size) { path in
            // Dome: left wall up, arc across the top, right wall down.
            path.move(to: CGPoint(x: 6, y: 19))
            path.addLine(to: CGPoint(x: 6, y: 11))
            path.addArc(
                withCenter: CGPoint(x: 12, y: 11),
                radius: 6,
                startAngle: .pi,
                endAngle: 0,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: 18, y: 19))
            // Base line.
            path.move(to: CGPoint(x: 4, y: 19))
            path.addLine(to: CGPoint(x: 20, y: 19))
            // Clapper.
            path.move(to: CGPoint(x: 10, y: 22))
            path.addLine(to: CGPoint(x: 14, y: 22))
        }
    }

    /// Динамик с волнами — speaker cone + two sound arcs. The alarm-sound
    /// pill glyph. JSX: `IconSound`
    /// (`M11 5L6 9H3v6h3l5 4V5z` / `M16 9a4 4 0 0 1 0 6` / `M19 6a8 8 0 0 1 0 12`).
    static func sound(size: CGFloat) -> UIImage {
        render(size: size) { path in
            // Speaker cone.
            path.move(to: CGPoint(x: 11, y: 5))
            path.addLine(to: CGPoint(x: 6, y: 9))
            path.addLine(to: CGPoint(x: 3, y: 9))
            path.addLine(to: CGPoint(x: 3, y: 15))
            path.addLine(to: CGPoint(x: 6, y: 15))
            path.addLine(to: CGPoint(x: 11, y: 19))
            path.close()
            // Inner wave: `M16 9a4 4 0 0 1 0 6` — quarter-pair arc on the right.
            path.move(to: CGPoint(x: 16, y: 9))
            path.addArc(
                withCenter: CGPoint(x: 16, y: 12),
                radius: 3,
                startAngle: -.pi / 2,
                endAngle: .pi / 2,
                clockwise: true
            )
            // Outer wave: `M19 6a8 8 0 0 1 0 12`.
            path.move(to: CGPoint(x: 19, y: 6))
            path.addArc(
                withCenter: CGPoint(x: 19, y: 12),
                radius: 6,
                startAngle: -.pi / 2,
                endAngle: .pi / 2,
                clockwise: true
            )
        }
    }

    /// «Zz» — большая Z + маленькая Z по диагонали. JSX: `IconSnooze`.
    static func snooze(size: CGFloat) -> UIImage {
        render(size: size) { path in
            path.move(to: CGPoint(x: 13, y: 5))
            path.addLine(to: CGPoint(x: 19, y: 5))
            path.addLine(to: CGPoint(x: 13, y: 13))
            path.addLine(to: CGPoint(x: 19, y: 13))
            path.move(to: CGPoint(x: 5, y: 13))
            path.addLine(to: CGPoint(x: 9, y: 13))
            path.addLine(to: CGPoint(x: 5, y: 18))
            path.addLine(to: CGPoint(x: 9, y: 18))
        }
    }

    // MARK: - Shared path fragments

    /// The ₽ glyph used by both the coin and coin-off variants:
    /// stem `M9 8v9`, bowl `M9 8h3.5a2.5 2.5 0 0 1 0 5H9`,
    /// crossbar `M7.5 14.5H13`.
    private static func rubleGlyph() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 9, y: 8))
        path.addLine(to: CGPoint(x: 9, y: 17))
        path.move(to: CGPoint(x: 9, y: 8))
        path.addLine(to: CGPoint(x: 12.5, y: 8))
        path.addArc(
            withCenter: CGPoint(x: 12.5, y: 10.5),
            radius: 2.5,
            startAngle: -.pi / 2,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: 9, y: 13))
        path.move(to: CGPoint(x: 7.5, y: 14.5))
        path.addLine(to: CGPoint(x: 13, y: 14.5))
        return path
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> UIBezierPath {
        UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: true
        )
    }

    // MARK: - Renderer

    /// SVG viewBox edge — all paths are authored on this grid.
    private static let gridSize: CGFloat = 24

    /// SVG `strokeWidth` in viewBox units; scales with the icon size.
    private static let strokeWidth: CGFloat = 1.75

    private static func render(size: CGFloat, build: (UIBezierPath) -> Void) -> UIImage {
        let path = UIBezierPath()
        build(path)

        let scale = size / gridSize
        path.apply(CGAffineTransform(scaleX: scale, y: scale))
        path.lineWidth = strokeWidth * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { _ in
            UIColor.white.setStroke()
            path.stroke()
        }
        // Template mode — tintColor plays the SVG's `currentColor`.
        return image.withRenderingMode(.alwaysTemplate)
    }
}
