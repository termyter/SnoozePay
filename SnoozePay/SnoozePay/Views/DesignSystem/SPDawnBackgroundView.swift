import UIKit

/// Atmospheric "Dawn" background view used by the V2 firing screen.
///
/// Spec — `docs/design/v2-handoff/components/SPScreensV2.jsx` lines 37–276 and
/// `SPDawnV3.jsx` (DawnAtmosphere). Three layers stacked under the content:
/// 1. **Base** — vertical linear gradient. The default Dawn recipe is
///    `#0A0E1A → #0E1320 → #1A1410` (cool night to warm horizon); the
///    no-balance "drained" variant collapses to `#0E1320 → #160B0B` so the
///    screen reads as colder + redder when the wallet is empty.
/// 2. **Overlay** — radial gradient anchored at the bottom centre (50% 100%),
///    blending warn-amber rgba(245,158,11,.22) → pain rgba(244,82,63,.10) →
///    transparent at 60%. Sells the "rising heat" cue.
/// 3. **Sun** — 480×480pt blurred circle anchored 180pt below the bottom edge
///    (`SPDawnV3.jsx:30-33`). Driven by either the warn or pain radial palette
///    depending on `tone`.
///
/// The view owns three CAGradientLayers (base, overlay, sun) and reflows them
/// on every layout pass so rotation / safe-area changes work without per-frame
/// recompute. The sun layer hosts the 8s opacity breathing animation so
/// `AlarmFiringViewController.startGlowBreathing()` keeps working unchanged.
final class SPDawnBackgroundView: UIView {

    // MARK: - Tone

    /// Atmospheric variant. Matches the JSX `DawnAtmosphere({ tone })` cases.
    enum Tone {
        /// Default calm Dawn — warm amber sun + cool night base.
        case calm
        /// Progressive escalation — pain coral sun + slightly redder base.
        case tense
        /// No-balance ("drained") — cold blue-grey sun, colder base.
        case drained
    }

    private(set) var tone: Tone

    // MARK: - Calm recipe (shared with the theme picker)

    /// Calm-tone base stops — `#0A0E1A → #0E1320 → #1A1410` (cool night to
    /// warm horizon). Exposed so `AlarmThemeRendering` can render the Dawn
    /// picker tile / preview as a true miniature of this background instead
    /// of the stale pre-#151 night gradient it used to carry (#463).
    static let calmBaseColors: [UIColor] = [
        UIColor(dawnRGB: 0x0A0E1A),
        UIColor(dawnRGB: 0x0E1320),
        UIColor(dawnRGB: 0x1A1410)
    ]

    /// Stop locations paired with `calmBaseColors` — mid-stop at 55% per
    /// `SPDawnV3.jsx:20` (`#0E1320 55%`).
    static let calmBaseLocations: [NSNumber] = [0.0, 0.55, 1.0]

    /// Core colour of the calm sun radial. The picker preview reuses it as the
    /// bottom glow so the Dawn thumbnail reads «тёплый янтарь» the way the
    /// firing screen does (#463).
    static let calmSunCoreColor = UIColor(dawnRGB: 0xFFB84D, alpha: 0.45)

    // MARK: - Layers

    /// Vertical 3-stop base. Spec colours come from JSX `palettes[tone].base`.
    private let baseLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .axial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        return gradient
    }()

    /// Radial "warm rising" overlay at 50% 100%, blends warn → pain → transparent.
    /// CALayer can render radial gradients via `.type = .radial` since iOS 12.
    private let overlayLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.endPoint = CGPoint(x: 1.4, y: 1.8)  // 140% radius / 70% height per spec
        return gradient
    }()

    /// 480×480 sun circle, anchored ~180pt below the bottom edge. Public so
    /// the firing VC can attach the 8s opacity breathing animation.
    let sunLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        // 480pt circle anchored ~180pt below the bottom edge — the upper
        // hemisphere bleeds into the screen as the rising warmth.
        return gradient
    }()

    // MARK: - Init

    init(tone: Tone = .calm) {
        self.tone = tone
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.addSublayer(baseLayer)
        layer.addSublayer(overlayLayer)
        layer.addSublayer(sunLayer)
        applyTone()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Swap the atmospheric palette in place. Used by the firing VC when the
    /// progressive snooze count crosses the "tense" threshold or when the
    /// balance drains to zero ("drained").
    func setTone(_ newTone: Tone) {
        guard newTone != tone else { return }
        tone = newTone
        applyTone()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = bounds
        baseLayer.frame = bounds
        overlayLayer.frame = bounds

        // Sun: 480×480pt whose BOTTOM sits 180pt below the screen edge
        // (`SPDawnV3.jsx:30` — `bottom: -180px`). Centered horizontally; the
        // upper hemisphere bleeds in as the rising glow.
        let sunSize: CGFloat = 480
        let sunY = bounds.height + 180 - sunSize
        sunLayer.frame = CGRect(
            x: (bounds.width - sunSize) / 2,
            y: sunY,
            width: sunSize,
            height: sunSize
        )
        sunLayer.cornerRadius = sunSize / 2
    }

    // MARK: - Internals

    private func applyTone() {
        // Disable implicit CAAction animations during tone swap so the
        // colours snap rather than cross-fade slowly on every setTone call.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        switch tone {
        case .calm: applyCalmTone()
        case .tense: applyTenseTone()
        case .drained: applyDrainedTone()
        }
    }

    private func applyCalmTone() {
        // Base: #0A0E1A → #0E1320 → #1A1410, mid-stop 0.55. Single table —
        // the picker preview reads the same statics (#463).
        baseLayer.colors = Self.calmBaseColors.map { $0.cgColor }
        baseLayer.locations = Self.calmBaseLocations
        // Overlay: warn 22% → pain 10% → transparent
        overlayLayer.colors = [
            UIColor(dawnRGB: 0xF59E0B, alpha: 0.22).cgColor,
            UIColor(dawnRGB: 0xF4523F, alpha: 0.10).cgColor,
            UIColor(dawnRGB: 0xF59E0B, alpha: 0.0).cgColor
        ]
        overlayLayer.locations = [0.0, 0.3, 0.6]
        // Sun: warm amber radial
        sunLayer.colors = [
            Self.calmSunCoreColor.cgColor,
            UIColor(dawnRGB: 0xF59E0B, alpha: 0.10).cgColor,
            UIColor(dawnRGB: 0xF59E0B, alpha: 0.0).cgColor
        ]
        sunLayer.locations = [0.0, 0.35, 0.7]
    }

    private func applyTenseTone() {
        // Base shifts red: #0A0E1A → #14101C → #240C0C
        baseLayer.colors = [
            UIColor(dawnRGB: 0x0A0E1A).cgColor,
            UIColor(dawnRGB: 0x14101C).cgColor,
            UIColor(dawnRGB: 0x240C0C).cgColor
        ]
        baseLayer.locations = [0.0, 0.5, 1.0]
        // Overlay leans pain
        overlayLayer.colors = [
            UIColor(dawnRGB: 0xF4523F, alpha: 0.24).cgColor,
            UIColor(dawnRGB: 0xD43A28, alpha: 0.12).cgColor,
            UIColor(dawnRGB: 0xF4523F, alpha: 0.0).cgColor
        ]
        overlayLayer.locations = [0.0, 0.3, 0.6]
        // Sun: pain radial
        sunLayer.colors = [
            UIColor(dawnRGB: 0xF4523F, alpha: 0.42).cgColor,
            UIColor(dawnRGB: 0xD43A28, alpha: 0.12).cgColor,
            UIColor(dawnRGB: 0xF4523F, alpha: 0.0).cgColor
        ]
        sunLayer.locations = [0.0, 0.35, 0.7]
    }

    private func applyDrainedTone() {
        // Base: cold blue-grey gradient, #0E1320 → #160B0B
        // (matches FiringNoBalanceV2 spec line 230)
        baseLayer.colors = [
            UIColor(dawnRGB: 0x0E1320).cgColor,
            UIColor(dawnRGB: 0x160B0B).cgColor
        ]
        baseLayer.locations = [0.0, 1.0]
        // Overlay: faint pain wash so the empty state still has heat
        overlayLayer.colors = [
            UIColor(dawnRGB: 0xF4523F, alpha: 0.10).cgColor,
            UIColor(dawnRGB: 0xF4523F, alpha: 0.04).cgColor,
            UIColor(dawnRGB: 0xF4523F, alpha: 0.0).cgColor
        ]
        overlayLayer.locations = [0.0, 0.3, 0.6]
        // Sun: cold blue-grey halo
        sunLayer.colors = [
            UIColor(dawnRGB: 0x788CB4, alpha: 0.18).cgColor,
            UIColor(dawnRGB: 0x3C5078, alpha: 0.06).cgColor,
            UIColor(dawnRGB: 0x788CB4, alpha: 0.0).cgColor
        ]
        sunLayer.locations = [0.0, 0.35, 0.7]
    }
}

// MARK: - Hex helper

private extension UIColor {
    /// `0xRRGGBB` initializer mirrored from sibling AlarmFiring files —
    /// `private` is file-scope in Swift, so each file that uses hex literals
    /// carries its own copy. Keeps the JSX spec → Swift literal mapping
    /// readable.
    convenience init(dawnRGB rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
