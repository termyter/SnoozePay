import UIKit

/// A `UILabel` that reports an intrinsic height matching the width it was
/// actually given.
///
/// A plain multi-line `UILabel` inside a stack view has a chicken-and-egg
/// problem: the stack measures the label before deciding how wide it will be,
/// and with no `preferredMaxLayoutWidth` the label answers with its
/// SINGLE-LINE size. The stack sizes itself to that one line; the label is
/// then squeezed narrower, wraps — and the extra lines have nowhere to be
/// drawn. Nothing looks broken from the layout engine's side: no constraint is
/// violated, no truncation glyph appears. The text simply stops.
///
/// That is how «Чаще, чем неделю назад» came to render as «Чаще, чем» with
/// half the card empty beside it (#631) — the wrap happened, the height did
/// not follow.
///
/// Re-reporting the intrinsic size once the real width is known closes the
/// loop. This is the standard UIKit answer for the case; the alternative —
/// pinning the label's width with a constraint — hard-codes a number the
/// design does not have.
final class SPWrappingLabel: UILabel {

    override func layoutSubviews() {
        super.layoutSubviews()
        // Guarded so a settled layout does not invalidate itself forever.
        guard abs(preferredMaxLayoutWidth - bounds.width) > 0.5 else { return }
        preferredMaxLayoutWidth = bounds.width
        invalidateIntrinsicContentSize()
    }
}
