import UIKit

/// V2 «Прогрессивный режим» card (#231, `SPMore2.jsx` AlarmEdit).
///
/// A single self-contained card: leading flame icon + h4 title, rationale
/// subtitle, the doubling chain `50 → 100 → 200 → 400 ₽` (visible while the
/// mode is armed) and a trailing `SPSwitch`. When armed, the card surface
/// flips to the pain-tinted gradient + pain hairline so the row reads as
/// "this will hurt" at a glance.
///
/// The cell owns its `backgroundView` (the host controller's generic
/// `styleAsCardRow` recipe is skipped for this cell) because the pain tint
/// must survive both the toggle flip and table re-measure passes.
final class ProgressiveScaleCell: UITableViewCell {

    static let reuseID = "ProgressiveScaleCell"

    // MARK: - UI

    private let surface = ProgressiveCardSurface()

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "flame.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        )
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fg3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.progressive.title")
        label.font = AppTypography.h4
        label.textColor = AppColors.fg1
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.progressive.subtitle")
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        return label
    }()

    /// `50 → 100 → 200 → 400 ₽` — mono digits, warn-tinted start, pain-tinted
    /// tail, final value rendered through `MoneyFormatter`.
    private let chainLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()

    /// The canon's `flex: 1` column — title row, subtitle and chain sit beside
    /// the switch, not under it (`SPMore2.jsx` L260).
    ///
    /// `.fill`, not `.leading`: under `.leading` every row kept its intrinsic
    /// width, which for a `numberOfLines = 0` label is its SINGLE-LINE width.
    /// The column then had no definite width of its own, so where the subtitle
    /// broke was decided by compression-resistance tie-breaks rather than by
    /// the space available — it wrapped at "в 2 / раза" with half the card
    /// still empty to its right (#638).
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let toggle = SPSwitch()

    // MARK: - Callbacks

    var onToggled: ((Bool) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        backgroundView = surface
        selectionStyle = .none

        let headerRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = AppSpacing.sp2

        contentStack.addArrangedSubview(headerRow)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.addArrangedSubview(chainLabel)
        contentStack.setCustomSpacing(6, after: headerRow)
        contentStack.setCustomSpacing(AppSpacing.sp3, after: subtitleLabel)

        toggle.translatesAutoresizingMaskIntoConstraints = false
        // VoiceOver otherwise reads the brand `SPSwitch` as the generic
        // «Переключатель». Give it the row's title so the control is
        // self-describing, mirroring AlarmCell's pattern (#425).
        toggle.accessibilityLabel = titleLabel.text

        contentView.addSubview(contentStack)
        contentView.addSubview(toggle)

        // Card padding 20pt on all sides (#231 `padding=20` rule); the switch
        // is top-aligned with the header row per the artboard's
        // `alignItems: flex-start`.
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.cardHorizontalPadding),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp5),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sp5),
            // `equalTo`, not `lessThanOrEqualTo`: the column has to CLAIM the
            // width the switch leaves it, which is what `flex: 1` does in the
            // canon. Merely capping it left the width indefinite (#638).
            contentStack.trailingAnchor.constraint(
                equalTo: toggle.leadingAnchor, constant: -AppSpacing.sp3
            ),

            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.cardHorizontalPadding),
            toggle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp5)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggled = nil
    }

    // MARK: - Configure

    /// - Parameters:
    ///   - isOn: Whether progressive mode is armed.
    ///   - chain: The four doubling steps (base, ×2, ×4, ×8) in roubles.
    ///   - accessibilityChain: Spoken form of the chain («1-е: 50 ₽ → …»).
    func configure(isOn: Bool, chain: [Int], accessibilityChain: String) {
        toggle.isOn = isOn
        chainLabel.attributedText = Self.chainText(for: chain)
        chainLabel.accessibilityLabel = accessibilityChain
        applyArmedAppearance(isOn)
    }

    // MARK: - Actions

    @objc private func toggled() {
        applyArmedAppearance(toggle.isOn)
        onToggled?(toggle.isOn)
    }

    private func applyArmedAppearance(_ isOn: Bool) {
        iconView.tintColor = isOn ? AppColors.pain400 : AppColors.fg3
        chainLabel.isHidden = !isOn
        surface.setPainTinted(isOn)
    }

    // MARK: - Chain rendering

    /// `50 → 100 → 200 → 400 ₽` per `SPMore2.jsx`: the first two steps are
    /// warn-tinted (still affordable), the back half pain-tinted, and the
    /// final step renders bold at 16pt with the rouble glyph via
    /// `MoneyFormatter` so the narrow-space rule holds.
    private static func chainText(for chain: [Int]) -> NSAttributedString {
        guard chain.count == 4 else { return NSAttributedString() }
        let stepFont = AppFonts.mono(.semibold, 14)
        let arrowAttributes: [NSAttributedString.Key: Any] = [
            .font: stepFont,
            .foregroundColor: AppColors.fg4
        ]
        let stepColors: [UIColor] = [
            AppColors.warn400, AppColors.warn400, AppColors.pain400
        ]

        let result = NSMutableAttributedString()
        for (index, value) in chain.prefix(3).enumerated() {
            result.append(NSAttributedString(
                string: MoneyFormatter.digits(value),
                attributes: [.font: stepFont, .foregroundColor: stepColors[index]]
            ))
            result.append(NSAttributedString(string: " → ", attributes: arrowAttributes))
        }
        result.append(MoneyFormatter.attributed(
            Decimal(chain[3]),
            digitsFont: AppFonts.mono(.bold, 16),
            color: AppColors.pain400
        ))
        return result
    }
}

// MARK: - Pain-tintable card surface

/// Card background for `ProgressiveScaleCell`. Default state mirrors the
/// generic `styleAsCardRow` recipe (`bg1` fill + brand shadow + `stroke1`
/// hairline); the armed state overlays the V2 pain gradient
/// (`135deg rgba(244,82,63,.10) → rgba(244,82,63,.02)`) and swaps the hairline
/// for the pain tint per `SPMore2.jsx`.
///
/// `internal` rather than file-private so the light-theme regression tests can
/// host it in a window — the decoration only resolves correctly inside a real
/// hierarchy (see `CreateAlarmLightThemeTests`).
final class ProgressiveCardSurface: UIView {

    /// Whether the card is currently showing its armed (pain-tinted) state.
    /// Kept so a theme flip can repaint the right hairline without the cell
    /// having to re-`configure`.
    private var isPainTinted = false

    private let gradient: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.cornerRadius = AppRadius.sm
        layer.isHidden = true
        return layer
    }()

    init() {
        super.init(frame: .zero)
        // `bg1`, not the system `secondarySystemBackground`: identical
        // `#FFFFFF` in light, but the brand `#0E1320` in dark instead of the
        // system's warm `#1C1C1E`. Every sibling section on this form is
        // painted by `CardRowBackgroundView`, which moved onto `bg1` in #496 —
        // this card was the last one still reading a different dark grey.
        backgroundColor = AppColors.bg1
        layer.cornerRadius = AppRadius.sm
        layer.masksToBounds = false
        layer.addSublayer(gradient)
        applyThemedDecoration()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ProgressiveCardSurface, _) in
            view.applyThemedDecoration()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: AppRadius.sm).cgPath
        // Light mode's `shadow1` is a two-stop recipe; the narrow ambient stop
        // lives on a sibling sublayer that has to track the host's bounds.
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: AppRadius.sm,
            trait: traitCollection
        )
    }

    func setPainTinted(_ isOn: Bool) {
        isPainTinted = isOn
        gradient.isHidden = !isOn
        applyThemedDecoration()
    }

    /// Re-resolve everything that caches a `cgColor` or branches on theme.
    ///
    /// The hairline is no longer armed-only: on the light page a white card on
    /// `#F4F6FB` is 1.06:1 of separation, so the border is what draws the card
    /// edge — the shadow alone leaves a floating slab. Disarmed the stroke is
    /// the neutral `stroke1` every other card uses; armed it becomes the pain
    /// tint from `SPMore2.jsx`.
    private func applyThemedDecoration() {
        AppShadow.shadow1(for: traitCollection).apply(to: layer)
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: AppRadius.sm,
            trait: traitCollection
        )
        gradient.colors = [
            AppColors.pain500.resolvedColor(with: traitCollection).withAlphaComponent(0.10).cgColor,
            AppColors.pain500.resolvedColor(with: traitCollection).withAlphaComponent(0.02).cgColor
        ]
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        layer.borderWidth = isPainTinted ? 1 : 1.0 / scale
        let stroke = isPainTinted
            ? AppColors.pain500.resolvedColor(with: traitCollection).withAlphaComponent(0.25)
            : AppColors.stroke1.resolvedColor(with: traitCollection)
        layer.borderColor = stroke.cgColor
    }
}
