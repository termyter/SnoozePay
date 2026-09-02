import UIKit

/// Segmented selector matching `.sp-seg` in `components.css`.
///
/// Visual: capsule background (`whiteOverlay06`), inset `sp1`, with a sliding
/// selection indicator that animates between segments at the brand
/// `--sp-dur-base` (220ms) duration. The selected segment shows a `bg1`
/// fill + `--sp-shadow-1` so it lifts off the capsule, matching the
/// iOS-native segmented look but recoloured for the brand.
///
/// Light theme: the indicator is pure white (`bg1`) sitting on a track that is
/// only a 6% ink wash, so the two surfaces differ by a couple of percent of
/// luminance and a drop shadow alone cannot draw the edge. The indicator
/// therefore carries a hairline border *in addition to* the shadow — light
/// mode only, so the dark canon is untouched.
final class SPSegmented: UIControl {

    // MARK: - Tokens & metrics
    //
    // Exposed rather than inlined at the call site so
    // `SPDesignSystemLightThemeTests` measures the colours this control
    // actually renders, not a copy of them.

    /// Capsule behind the segments — `.sp-seg` background.
    static let trackColor = AppColors.whiteOverlay06
    /// Active-segment fill — `.sp-seg__opt.is-on`.
    static let indicatorColor = AppColors.bg1
    /// Idle segment label.
    static let idleTitleColor = AppColors.fg3
    /// Active segment label.
    static let selectedTitleColor = AppColors.fg1

    /// `.sp-seg__opt { border-radius: 10px }` — the active indicator nests
    /// inside the 12pt track with a fixed 10pt radius.
    private static let indicatorCornerRadius: CGFloat = 10
    /// `.sp-seg { gap: 2px }` — deliberately off the 4pt grid: it only keeps
    /// adjacent hit areas from touching, it is not layout rhythm.
    private static let segmentGap: CGFloat = 2
    /// Minimum comfortable control height (HIG touch target).
    private static let controlHeight: CGFloat = 44

    /// Single option: stable `value` ID + display `label`.
    struct Option {
        let value: String
        let label: String
    }

    // MARK: - State

    private(set) var options: [Option]
    /// Currently selected `value`. Setting programmatically does not fire
    /// `onChange` — only user interaction does. Triggers a slide animation
    /// of the selection indicator.
    var selectedValue: String? {
        didSet { updateSelection(animated: oldValue != selectedValue) }
    }

    /// Closure fired on user-driven selection change. Receives the new
    /// `value`. Storing as a closure (rather than a delegate) keeps simple
    /// SwiftUI-like call sites idiomatic.
    var onChange: ((String) -> Void)?

    // MARK: - Subviews

    private let track = UIView()
    private let indicator = UIView()
    private var segmentButtons: [UIButton] = []

    // MARK: - Init

    /// - Parameters:
    ///   - options: Ordered list of (value, label) pairs.
    ///   - selectedValue: Initial selection — must match one of the option
    ///     values, otherwise no segment is shown as selected.
    ///   - onChange: Selection callback.
    init(
        options: [Option],
        selectedValue: String? = nil,
        onChange: ((String) -> Void)? = nil
    ) {
        self.options = options
        self.selectedValue = selectedValue
        self.onChange = onChange
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = AppRadius.sm
        track.layer.cornerRadius = AppRadius.sm
        indicator.layer.cornerRadius = Self.indicatorCornerRadius
        // Re-position indicator after layout cycle resolves geometries.
        positionIndicator(animated: false)
        // The ambient stop of `--sp-shadow-1` is a sublayer whose frame has to
        // track the indicator, so re-install it once geometry has settled.
        applyIndicatorElevation()
    }

    // MARK: - Configuration

    private func configure() {
        // Owns its autoresizing flag. This view activates a required
        // `heightAnchor` on ITSELF (below), which cannot coexist with the
        // constraints UIKit synthesises from the `.zero` frame it is born
        // with. A caller who forgets the reset gets no error: the engine pays
        // for the collision out of whatever else is breakable, which in #467
        // was the intrinsic height of the SIBLINGS — they kept their
        // x/y/width and measured 0 tall, and the screen read as blank. Owning
        // it here makes forgetting impossible; call sites that still set it
        // are harmlessly redundant (#584).
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .clear

        track.translatesAutoresizingMaskIntoConstraints = false
        track.backgroundColor = Self.trackColor
        addSubview(track)

        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.backgroundColor = Self.indicatorColor
        indicator.layer.masksToBounds = false
        // `.sp-seg__opt.is-on { box-shadow: var(--sp-shadow-1) }` — soft lift
        // so the active option floats off the track.
        applyIndicatorElevation()
        track.addSubview(indicator)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = Self.segmentGap
        stack.isUserInteractionEnabled = true
        track.addSubview(stack)

        segmentButtons = options.enumerated().map { index, option in
            let button = UIButton(type: .system)
            button.setTitle(option.label, for: .normal)
            button.titleLabel?.font = AppTypography.buttonSm
            button.tag = index
            button.tintColor = .clear   // disable the iOS blue tint reflow
            button.setTitleColor(Self.idleTitleColor, for: .normal)
            button.setTitleColor(Self.selectedTitleColor, for: .selected)
            button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            return button
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.controlHeight),
            track.topAnchor.constraint(equalTo: topAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: track.topAnchor, constant: AppSpacing.sp1),
            stack.bottomAnchor.constraint(equalTo: track.bottomAnchor, constant: -AppSpacing.sp1),
            stack.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: AppSpacing.sp1),
            stack.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: -AppSpacing.sp1)
        ])
        registerTraitObserver()
        updateSelection(animated: false)
    }

    // MARK: - Elevation

    /// Install `--sp-shadow-1` on the active indicator, theme-aware.
    ///
    /// This used to be a hand-written `rgba(0,0,0,.35)` drop — the *dark* stop
    /// of the token, applied in both themes. On a near-white track that reads
    /// as a grey smudge rather than a lift, and it left the white indicator
    /// with no defined edge at all. `AppShadow` supplies the two-stop light
    /// recipe; the hairline below supplies the edge.
    private func applyIndicatorElevation() {
        AppShadow.shadow1(for: traitCollection).apply(to: indicator.layer)
        AppShadow.installAmbientShadow1Layer(
            on: indicator.layer,
            cornerRadius: Self.indicatorCornerRadius,
            trait: traitCollection
        )
        guard traitCollection.userInterfaceStyle != .dark else {
            indicator.layer.borderWidth = 0
            return
        }
        indicator.layer.borderWidth = hairlineWidth
        indicator.layer.borderColor = AppColors.stroke1
            .resolvedColor(with: traitCollection).cgColor
    }

    /// `CALayer` stores a *resolved* `cgColor`, so dynamic tokens have to be
    /// re-installed by hand whenever the theme flips.
    private func registerTraitObserver() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPSegmented, _) in
                view.applyIndicatorElevation()
            }
        }
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        applyIndicatorElevation()
    }

    @objc
    private func handleTap(_ sender: UIButton) {
        guard sender.tag < options.count else { return }
        let value = options[sender.tag].value
        guard value != selectedValue else { return }
        selectedValue = value
        onChange?(value)
        sendActions(for: .valueChanged)
    }

    private func updateSelection(animated: Bool) {
        for (index, button) in segmentButtons.enumerated() {
            let isOn = options[index].value == selectedValue
            button.isSelected = isOn
        }
        if animated {
            UIView.animate(
                withDuration: SPSupport.durationBase,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState],
                animations: { self.positionIndicator(animated: true) },
                completion: nil
            )
        } else {
            positionIndicator(animated: false)
        }
    }

    private func positionIndicator(animated: Bool) {
        guard
            let selected = selectedValue,
            let index = options.firstIndex(where: { $0.value == selected }),
            index < segmentButtons.count,
            track.bounds.width > 0
        else {
            indicator.isHidden = true
            return
        }
        indicator.isHidden = false
        let target = segmentButtons[index]
        // Position the indicator inside the track using its frame in track
        // coordinates — track is laid out in `bounds` already.
        let frame = target.convert(target.bounds, to: track)
        indicator.frame = frame
        // Pre-rasterise the shadow against the rounded rect so the lift does
        // not cost an offscreen pass on every slide.
        indicator.layer.shadowPath = UIBezierPath(
            roundedRect: indicator.bounds,
            cornerRadius: Self.indicatorCornerRadius
        ).cgPath
    }
}
