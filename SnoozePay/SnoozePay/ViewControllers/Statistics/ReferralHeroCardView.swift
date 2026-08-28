import UIKit

/// Referral hero — the deep-green promo panel at the top of
/// `ReferralViewController` (`SPMore4.jsx` lines 244-257, `Referral()`):
/// caps eyebrow + h1 payout + body explainer over a 135° gradient.
///
/// Its own view rather than a `UIView` assembled inline in the controller for
/// two reasons:
///
///  1. `CAGradientLayer.colors` stores *resolved* `CGColor`s. Now that the
///     stops are theme-aware (`AppColors.heroDeep*`), someone has to re-apply
///     them when the theme flips — a bare sublayer silently keeps the previous
///     theme's colours, which is exactly how this screen ended up painted in
///     dark-theme colours under the light theme (#497).
///  2. The fill is dark in BOTH themes, so the copy is white in both. That is
///     `AppColors.fgOnHeroDeep` — deliberately *not* `fgOnMoney`, whose
///     dark-theme mint ink would disappear into the panel.
///
/// The shadow lives on `self` (`masksToBounds = false`) while the gradient
/// lives on an inner clipped `SPGradientView`, because one layer cannot both
/// clip its content and cast a shadow.
final class ReferralHeroCardView: UIView {

    // MARK: - Subviews

    private let fill: SPGradientView

    /// Style the gradient/shadow were last resolved for. Re-applying the stops
    /// on every layout pass would kick off an implicit `CAGradientLayer`
    /// animation, so the work is gated on an actual theme change.
    private var appliedStyle: UIUserInterfaceStyle?

    // MARK: - Init

    init(caps: String, headline: String, body: String) {
        fill = SPGradientView(
            colors: SPSupport.heroDeepGradientColors(for: .current),
            locations: SPSupport.heroDeepGradientLocations
        )
        super.init(frame: .zero)
        configureContainer()
        configureContent(caps: caps, headline: headline, body: body)
        applyTheme()
        registerTraitObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Pre-rasterise the shadow so the hero doesn't pay an offscreen pass
        // while the screen scrolls.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: AppRadius.xl
        ).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        applyTheme()
    }

    // MARK: - Setup

    private func configureContainer() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = AppRadius.xl
        layer.cornerCurve = .continuous
        layer.masksToBounds = false

        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.layer.cornerRadius = AppRadius.xl
        fill.layer.cornerCurve = .continuous
        fill.layer.masksToBounds = true
        addSubview(fill)
        NSLayoutConstraint.activate([
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func configureContent(caps: String, headline: String, body: String) {
        let eyebrow = SPSupport.makeCapsLabel(
            caps,
            color: AppColors.fgOnHeroDeep.withAlphaComponent(0.7)
        )
        eyebrow.numberOfLines = 0

        let title = UILabel()
        title.font = AppTypography.h1
        title.textColor = AppColors.fgOnHeroDeep
        title.numberOfLines = 0
        title.text = headline
        title.translatesAutoresizingMaskIntoConstraints = false

        let explainer = UILabel()
        explainer.text = body
        explainer.font = AppTypography.body
        explainer.textColor = AppColors.fgOnHeroDeep.withAlphaComponent(0.85)
        explainer.numberOfLines = 0
        explainer.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [eyebrow, title, explainer])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = AppSpacing.sp2
        stack.setCustomSpacing(AppSpacing.sp3, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.sp7),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sp7),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.sp7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.sp7)
        ])
    }

    // MARK: - Theme

    /// iOS 17 replaced `traitCollectionDidChange(_:)` with the closure-based
    /// `registerForTraitChanges(_:handler:)`; keep the legacy override below
    /// for iOS 15/16. Same split as `SPCard`.
    private func registerTraitObserver() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ReferralHeroCardView, _) in
                view.applyTheme()
            }
        }
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        applyTheme()
    }

    private func applyTheme() {
        guard appliedStyle != traitCollection.userInterfaceStyle else { return }
        appliedStyle = traitCollection.userInterfaceStyle
        fill.refresh(
            colors: SPSupport.heroDeepGradientColors(for: traitCollection),
            locations: SPSupport.heroDeepGradientLocations
        )
        // `shadow2` is the "hero panel" recipe: on the light page it is what
        // lifts the dark panel off `bg0`, in the dark theme it keeps the panel
        // reading as elevated rather than as a hole in the background.
        AppShadow.shadow2(for: traitCollection).apply(to: layer)
    }
}
