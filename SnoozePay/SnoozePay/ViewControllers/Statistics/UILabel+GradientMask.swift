import UIKit

/// Render the label's text with a CALayer gradient masked to the rendered
/// glyphs — the iOS analogue of CSS's `-webkit-background-clip: text`.
///
/// Same recipe as `SPBalanceCard.applyValueGradient(...)`. Lifted into a
/// label-scoped helper here so `StatisticsViewController` can reuse it for
/// the pain-tinted "Потрачено" amount without growing the VC past the
/// SwiftLint type-body cap.
///
/// The helper takes over the label's painting entirely (`textColor` becomes
/// `.clear`), so it has to reproduce UILabel's own layout rules rather than
/// inherit `String.draw`'s defaults — see `applyGradientMask` for the two
/// that bit us in #347.
extension UILabel {

    /// Install (or refresh) the supplied gradient layer as a sublayer of the
    /// label and mask it to the current glyph outlines. Caller is responsible
    /// for keeping `gradient` alive (a stored property is the typical
    /// pattern) and for invoking this from `viewDidLayoutSubviews` so the
    /// mask stays in sync with text / size changes.
    ///
    /// `textColor` is set to `.clear` once the mask lands so the underlying
    /// label paint doesn't double-stack with the gradient — the caller can
    /// still set a non-clear `textColor` as a safety net before this runs.
    ///
    /// The mask honours:
    /// - **`textAlignment`**, via an explicit `NSParagraphStyle`. Without it
    ///   `String.draw(in:)` falls back to `.natural` — which pinned a
    ///   `.center` money hero to the left edge of its full-width label (#347).
    /// - **`adjustsFontSizeToFitWidth` / `minimumScaleFactor`**: the mask is
    ///   rasterised at the size UILabel itself would have shrunk to, so a long
    ///   amount scales down instead of being clipped mid-digit (a clipped
    ///   money figure reads as a *different, wrong* number).
    /// - **`numberOfLines`**: a multi-line label wraps inside the mask too.
    func applyGradientMask(_ gradient: CAGradientLayer) {
        let textBounds = bounds
        guard textBounds.width > 0,
              textBounds.height > 0,
              let text, !text.isEmpty,
              let font else { return }

        if gradient.superlayer !== layer {
            layer.addSublayer(gradient)
        }
        gradient.frame = textBounds

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineBreakMode = numberOfLines == 1 ? .byClipping : lineBreakMode

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
        )
        // Re-font to whatever `adjustsFontSizeToFitWidth` would have shrunk the
        // glyphs to. Same helper (and therefore the same clamping rules) as the
        // balance card's mask — see `SPBalanceCardGradientMaskTests` (#397).
        if adjustsFontSizeToFitWidth, numberOfLines == 1 {
            let scale = SPBalanceCard.effectiveFontScale(
                for: attributed,
                fitting: textBounds.width,
                minimumScaleFactor: minimumScaleFactor
            )
            if scale < 1 {
                SPBalanceCard.scaleFonts(in: attributed, by: scale)
            }
        }

        // Vertically centre the drawn run inside the label box the way UILabel
        // does; `draw(with:)` would otherwise top-align it.
        let fitting = attributed.boundingRect(
            with: CGSize(width: textBounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size
        let drawHeight = min(ceil(fitting.height), textBounds.height)
        let drawRect = CGRect(
            x: 0,
            y: ((textBounds.height - drawHeight) / 2).rounded(),
            width: textBounds.width,
            height: drawHeight
        )

        let renderer = UIGraphicsImageRenderer(size: textBounds.size)
        let mask = renderer.image { _ in
            attributed.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        let maskLayer = CALayer()
        maskLayer.frame = textBounds
        maskLayer.contents = mask.cgImage
        gradient.mask = maskLayer
        textColor = .clear
    }

}
