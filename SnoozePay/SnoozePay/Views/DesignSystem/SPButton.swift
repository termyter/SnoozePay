import UIKit

/// Branded button primitive matching the `.sp-btn` recipe in
/// `docs/design/snoozepay-2026-04-27/project/components/components.css`.
///
/// Three axes:
/// - `Variant`: visual chrome (gradient fills for money/pain/warn,
///   stroked-transparent for ghost, faint overlay for quiet).
/// - `Size`: 56pt / 48pt / 36pt heights with matching typography ramps.
/// - Optional `icon` (left) and `suffix` (right, mono-font) decorations.
///
/// All gradient variants install a `CAGradientLayer` at the bottom of the
/// view's layer tree and refresh it on layout / trait changes — `tintColor`
/// alone can't reproduce the 3-stop diagonal sweep the design calls for.
final class SPButton: UIControl {

    // MARK: - Variants

    enum Variant {
        case money   // Primary CTA — money gradient + fgOnMoney text.
        case pain    // Stop / delete / progressive snooze — pain gradient.
        case warn    // Default snooze — warn gradient.
        case ghost   // Transparent fill, stroke2 border.
        case quiet   // No chrome, faint overlay fill.
    }

    // Short cases mirror the JSX spec (`size="lg"`/`"md"`/`"sm"`) and the
    // `--sp-btn--{lg,md,sm}` CSS modifiers — keeping the names here makes
    // grep across CSS / JSX / Swift trivial.
    // swiftlint:disable identifier_name
    enum Size {
        case lg   // 56pt — primary CTA
        case md   // 48pt — secondary actions
        case sm   // 36pt — chips / inline buttons
        // swiftlint:enable identifier_name

        var height: CGFloat {
            switch self {
            case .lg: return 56
            case .md: return 48
            case .sm: return 36
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .lg, .md: return AppSpacing.sp6   // 24pt
            case .sm:      return 14
            }
        }

        var labelFont: UIFont {
            switch self {
            case .lg: return AppFonts.sans(.bold, 17)
            case .md: return AppTypography.button
            case .sm: return AppTypography.buttonSm
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .lg: return AppRadius.lg          // 16pt — matches sp-r-md
            case .md: return AppRadius.lg
            case .sm: return AppRadius.md          // 12pt — matches sp-r-sm
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .lg: return 20
            case .md: return 18
            case .sm: return 16
            }
        }
    }

    // MARK: - Configuration

    let variant: Variant
    let size: Size

    // MARK: - State

    /// Override `isEnabled` to refresh visual state — UIControl's default
    /// implementation only flips a property, not the rendered appearance.
    override var isEnabled: Bool {
        didSet { refreshDisabledAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { SPSupport.animatePress(self, pressed: isHighlighted) }
    }

    /// `false` by default — caller sizes the button explicitly. When `true`
    /// the button stretches to match its superview width via the trailing
    /// constraint installed by the parent.
    var isFullWidth: Bool = false {
        didSet { invalidateIntrinsicContentSize() }
    }

    // MARK: - Subviews

    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let suffixLabel = UILabel()
    private var gradientLayer: CAGradientLayer?

    // MARK: - Init

    /// - Parameters:
    ///   - title: Button label.
    ///   - variant: Visual chrome.
    ///   - size: Vertical scale. Defaults to `.lg`.
    ///   - icon: Optional leading image (rendered as template, tinted to
    ///     match the label colour).
    ///   - suffix: Optional trailing mono-font string (used for amounts,
    ///     e.g. "−50 ₽" suffixes on quick-pay buttons).
    ///   - fullWidth: When `true`, intrinsic width returns `noIntrinsicMetric`
    ///     so the caller can pin the button to its superview's width.
    init(
        title: String,
        variant: Variant = .money,
        size: Size = .lg,
        icon: UIImage? = nil,
        suffix: String? = nil,
        fullWidth: Bool = false
    ) {
        self.variant = variant
        self.size = size
        self.isFullWidth = fullWidth
        super.init(frame: .zero)
        configureLayout()
        titleLabel.text = title
        if let icon = icon {
            iconView.image = icon.withRenderingMode(.alwaysTemplate)
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
        if let suffix = suffix {
            suffixLabel.text = suffix
            suffixLabel.isHidden = false
        } else {
            suffixLabel.isHidden = true
        }
        applyVariant()
        refreshDisabledAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        // Honour `isFullWidth` by returning .noIntrinsicMetric for the width
        // axis — caller pins to superview / stack so the button stretches.
        let height = size.height
        if isFullWidth {
            return CGSize(width: UIView.noIntrinsicMetric, height: height)
        }
        let stackSize = stack.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize
        )
        return CGSize(
            width: stackSize.width + size.horizontalPadding * 2,
            height: height
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: size.cornerRadius
        ).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyVariant()
    }

    // MARK: - Configuration internals

    private func configureLayout() {
        layer.cornerRadius = size.cornerRadius
        layer.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = size.labelFont
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = false

        suffixLabel.translatesAutoresizingMaskIntoConstraints = false
        // Mono font for trailing amount suffixes — matches CSS recipe
        // `font-family: var(--sp-font-mono); opacity: .85`.
        suffixLabel.font = size == .sm ? AppTypography.moneySm : AppTypography.moneyMd
        suffixLabel.textAlignment = .right
        suffixLabel.alpha = 0.85
        suffixLabel.setContentHuggingPriority(.required, for: .horizontal)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = AppSpacing.sp2     // 8pt — matches `gap: 8px`
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(suffixLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: size.height),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: size.horizontalPadding
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -size.horizontalPadding
            ),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: size.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: size.iconSize)
        ])
    }

    private func applyVariant() {
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
        layer.borderWidth = 0
        layer.shadowOpacity = 0

        switch variant {
        case .money:
            installGradient(
                colors: SPSupport.moneyGradientColors,
                locations: SPSupport.moneyGradientLocations
            )
            applyColoredShadow(color: AppColors.money500)
            setForeground(AppColors.fgOnMoney)
        case .pain:
            installGradient(
                colors: SPSupport.painGradientColors,
                locations: SPSupport.painGradientLocations
            )
            applyColoredShadow(color: AppColors.pain500)
            setForeground(AppColors.fgOnPain)
        case .warn:
            installGradient(
                colors: SPSupport.warnGradientColors,
                locations: SPSupport.warnGradientLocations
            )
            applyColoredShadow(color: AppColors.warn500)
            setForeground(AppColors.fgOnWarn)
        case .ghost:
            backgroundColor = .clear
            let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
            layer.borderWidth = 1.0 / scale
            layer.borderColor = AppColors.stroke2.resolvedColor(with: traitCollection).cgColor
            setForeground(AppColors.fg1)
        case .quiet:
            backgroundColor = AppColors.whiteOverlay06
            setForeground(AppColors.fg1)
        }
    }

    private func installGradient(colors: [CGColor], locations: [NSNumber]) {
        let gradient = CAGradientLayer()
        gradient.colors = colors
        gradient.locations = locations
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.cornerRadius = size.cornerRadius
        layer.insertSublayer(gradient, at: 0)
        gradientLayer = gradient
        backgroundColor = .clear
    }

    private func applyColoredShadow(color: UIColor) {
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .light ? 0.30 : 0.40
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 16
    }

    private func setForeground(_ color: UIColor) {
        titleLabel.textColor = color
        suffixLabel.textColor = color
        iconView.tintColor = color
    }

    private func refreshDisabledAppearance() {
        // CSS recipe `is-disabled { opacity: .35; box-shadow: none;
        // filter: grayscale(.5); }` — we drop the shadow + alpha; the
        // grayscale hint is too expensive on a CALayer for the tiny visual
        // win, so we instead darken via reduced alpha which reads similarly.
        alpha = isEnabled ? 1.0 : 0.35
        if !isEnabled {
            layer.shadowOpacity = 0
        } else {
            applyVariant()
        }
    }
}
