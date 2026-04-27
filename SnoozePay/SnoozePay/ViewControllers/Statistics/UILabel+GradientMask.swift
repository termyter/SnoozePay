import UIKit

/// Render the label's text with a CALayer gradient masked to the rendered
/// glyphs — the iOS analogue of CSS's `-webkit-background-clip: text`.
///
/// Same recipe as `SPBalanceCard.applyValueGradient(...)` and
/// `StreakModalViewController.applyAmountGradient(...)`. Lifted into a
/// label-scoped helper here so `StatisticsViewController` can reuse it for
/// the pain-tinted "Потрачено" amount without growing the VC past the
/// SwiftLint type-body cap.
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
    func applyGradientMask(_ gradient: CAGradientLayer) {
        let textBounds = bounds
        guard textBounds.width > 0,
              textBounds.height > 0,
              text?.isEmpty == false else { return }

        if gradient.superlayer !== layer {
            layer.addSublayer(gradient)
        }
        gradient.frame = textBounds

        let renderer = UIGraphicsImageRenderer(size: textBounds.size)
        let mask = renderer.image { _ in
            (text ?? "").draw(
                in: textBounds,
                withAttributes: [
                    .font: font as Any,
                    .foregroundColor: UIColor.white
                ]
            )
        }
        let maskLayer = CALayer()
        maskLayer.frame = textBounds
        maskLayer.contents = mask.cgImage
        gradient.mask = maskLayer
        textColor = .clear
    }
}
