import UIKit

/// Segmented selector matching `.sp-seg` in `components.css`.
///
/// Visual: capsule background (`whiteOverlay06`), inset 4pt, with a sliding
/// selection indicator that animates between segments at the brand
/// `--sp-dur-base` (220ms) duration. The selected segment shows a `bg1`
/// fill + soft shadow so it lifts off the capsule, matching the iOS-native
/// segmented look but recoloured for the brand.
final class SPSegmented: UIControl {

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
        layer.cornerRadius = AppRadius.md
        track.layer.cornerRadius = AppRadius.md
        // Indicator slides into place via constraints; corner radius scales
        // with track padding so it visually nests.
        indicator.layer.cornerRadius = AppRadius.md - 4
        // Re-position indicator after layout cycle resolves geometries.
        positionIndicator(animated: false)
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = .clear

        track.translatesAutoresizingMaskIntoConstraints = false
        track.backgroundColor = AppColors.whiteOverlay06
        addSubview(track)

        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.backgroundColor = AppColors.bg1
        indicator.layer.shadowColor = UIColor.black.cgColor
        indicator.layer.shadowOpacity = 0.18
        indicator.layer.shadowOffset = CGSize(width: 0, height: 2)
        indicator.layer.shadowRadius = 6
        track.addSubview(indicator)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.isUserInteractionEnabled = true
        track.addSubview(stack)

        segmentButtons = options.enumerated().map { index, option in
            let button = UIButton(type: .system)
            button.setTitle(option.label, for: .normal)
            button.titleLabel?.font = AppTypography.buttonSm
            button.tag = index
            button.tintColor = .clear   // disable the iOS blue tint reflow
            button.setTitleColor(AppColors.fg3, for: .normal)
            button.setTitleColor(AppColors.fg1, for: .selected)
            button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            return button
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            track.topAnchor.constraint(equalTo: topAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: track.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: track.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: -4)
        ])
        updateSelection(animated: false)
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
    }
}
