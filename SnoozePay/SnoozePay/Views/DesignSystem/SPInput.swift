import UIKit

/// Branded text input wrapper — `.sp-input` in `components.css`.
///
/// Layout: optional caps label on top, then a 52pt-tall field with `bg2`
/// fill, 1.5pt `stroke1` border, 16pt internal padding. Optional trailing
/// view (icon button, character counter, ...). Hint / error message slot
/// underneath.
///
/// Wraps a vanilla `UITextField` rather than subclassing it — composition
/// keeps the field free for direct configuration (placeholder, keyboard
/// type, secure entry, ...) without us hiding behind a delegate proxy.
final class SPInput: UIView {

    // MARK: - Public surface

    /// The wrapped text field — call sites configure keyboard / secure
    /// entry / delegate / first-responder behaviour directly on it.
    let textField = UITextField()

    /// Hint string shown below the field. `nil` hides the hint slot.
    var hint: String? {
        get { hintLabel.text }
        set {
            hintLabel.text = newValue
            hintLabel.textColor = AppColors.fg3
            updateMessageVisibility()
        }
    }

    /// Error string. Setting a non-nil value flips the field border to
    /// `pain500` and tints the message line. Pass `nil` to clear.
    var error: String? {
        didSet { applyError() }
    }

    /// Optional trailing accessory (icon, button, label). Replaces any
    /// previous trailing view.
    var trailingView: UIView? {
        didSet { rebuildTrailing() }
    }

    /// Closure fired on every text change. Convenience over manual
    /// `addTarget(_:action:for:.editingChanged)` wiring — caller still has
    /// the option to set a `UITextFieldDelegate` for finer-grained events.
    var onChange: ((String) -> Void)?

    // MARK: - Subviews

    private let labelView = UILabel()
    private let fieldContainer = UIView()
    private let hintLabel = UILabel()
    private let trailingContainer = UIView()
    private var stack: UIStackView!

    // MARK: - Init

    /// - Parameters:
    ///   - label: Optional caps label above the field.
    ///   - placeholder: Field placeholder.
    ///   - text: Initial text.
    ///   - trailing: Optional trailing accessory view.
    ///   - hint: Optional helper line.
    ///   - error: Optional error line — flips field to error state when
    ///     non-nil.
    init(
        label: String? = nil,
        placeholder: String? = nil,
        text: String? = nil,
        trailing: UIView? = nil,
        hint: String? = nil,
        error: String? = nil
    ) {
        super.init(frame: .zero)
        configure()
        // iOS 17 deprecated `traitCollectionDidChange(_:)` — register a
        // closure-based observer when available, fall back to the override
        // below on older runtimes.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPInput, _) in
                view.applyBorder()
            }
        }
        if let label = label {
            labelView.attributedText = NSAttributedString(
                string: label.uppercased(),
                attributes: [
                    .font: AppTypography.caps,
                    .kern: 12 * 0.12,
                    .foregroundColor: AppColors.fg3
                ]
            )
            labelView.isHidden = false
        } else {
            labelView.isHidden = true
        }
        textField.placeholder = placeholder
        textField.text = text
        self.trailingView = trailing
        self.hint = hint
        self.error = error
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        fieldContainer.layer.cornerRadius = AppRadius.md     // matches sp-r-md
        // `.sp-input__field:focus-within { box-shadow: 0 0 0 4px rgba(...,.12) }`
        // is a hard 4pt ring (spread, zero blur). CALayer has no spread, so we
        // expand the shadowPath 4pt past the field and keep `shadowRadius` near
        // zero — that renders a crisp outline rather than a diffuse glow.
        fieldContainer.layer.shadowPath = UIBezierPath(
            roundedRect: fieldContainer.bounds.insetBy(dx: -4, dy: -4),
            cornerRadius: AppRadius.md + 4
        ).cgPath
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // iOS 17+ runtimes get the same callback through the registered
        // trait observer (see init); skip here so we don't refresh twice.
        if #available(iOS 17.0, *) { return }
        applyBorder()
    }

    // MARK: - First responder forwarding

    override var canBecomeFirstResponder: Bool { textField.canBecomeFirstResponder }

    @discardableResult
    override func becomeFirstResponder() -> Bool { textField.becomeFirstResponder() }

    @discardableResult
    override func resignFirstResponder() -> Bool { textField.resignFirstResponder() }

    // MARK: - Configuration

    private func configure() {
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.numberOfLines = 1

        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.backgroundColor = AppColors.bg2
        fieldContainer.layer.cornerRadius = AppRadius.md
        fieldContainer.layer.borderWidth = 1.5
        // Pre-configure the focus ring so editingDidBegin only has to flip
        // shadowOpacity. Money400 (`#2EDB9F`), zero blur + zero offset — the
        // expanded shadowPath in `layoutSubviews` turns it into a hard 4pt
        // ring. Kept off by default (opacity 0) so the field reads flat at rest.
        fieldContainer.layer.shadowColor = AppColors.money400.cgColor
        fieldContainer.layer.shadowRadius = 0
        fieldContainer.layer.shadowOpacity = 0
        fieldContainer.layer.shadowOffset = .zero
        fieldContainer.layer.masksToBounds = false

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = AppTypography.bodyLg
        textField.textColor = AppColors.fg1
        textField.tintColor = AppColors.money500
        textField.addTarget(self, action: #selector(handleEditingDidBegin), for: .editingDidBegin)
        textField.addTarget(self, action: #selector(handleEditingDidEnd), for: .editingDidEnd)
        textField.addTarget(self, action: #selector(handleEditingChanged), for: .editingChanged)

        trailingContainer.translatesAutoresizingMaskIntoConstraints = false

        let fieldRow = UIStackView(arrangedSubviews: [textField, trailingContainer])
        fieldRow.translatesAutoresizingMaskIntoConstraints = false
        fieldRow.axis = .horizontal
        fieldRow.alignment = .center
        fieldRow.spacing = AppSpacing.sp2
        fieldContainer.addSubview(fieldRow)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = AppTypography.meta
        hintLabel.textColor = AppColors.fg3
        hintLabel.numberOfLines = 0
        hintLabel.isHidden = true

        stack = UIStackView(arrangedSubviews: [labelView, fieldContainer, hintLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),

            fieldContainer.heightAnchor.constraint(equalToConstant: 52),
            fieldRow.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            fieldRow.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            fieldRow.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 16),
            fieldRow.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -16)
        ])
        applyBorder()
    }

    private func rebuildTrailing() {
        trailingContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let view = trailingView else {
            trailingContainer.isHidden = true
            return
        }
        trailingContainer.isHidden = false
        view.translatesAutoresizingMaskIntoConstraints = false
        trailingContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: trailingContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: trailingContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: trailingContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingContainer.trailingAnchor)
        ])
    }

    private func applyBorder() {
        if error != nil {
            fieldContainer.layer.borderColor = AppColors.pain500.cgColor
        } else if textField.isFirstResponder {
            fieldContainer.layer.borderColor = AppColors.money500.cgColor
        } else {
            fieldContainer.layer.borderColor = AppColors.stroke1
                .resolvedColor(with: traitCollection).cgColor
        }
        // Re-resolve the focus ring tint (money400 per the CSS recipe) so a
        // light/dark switch keeps the ring colour stable.
        fieldContainer.layer.shadowColor = AppColors.money400
            .resolvedColor(with: traitCollection).cgColor
    }

    private func applyError() {
        if let error = error {
            hintLabel.text = error
            hintLabel.textColor = AppColors.pain400
            hintLabel.isHidden = false
        } else if let hint = hint, !hint.isEmpty {
            hintLabel.text = hint
            hintLabel.textColor = AppColors.fg3
            hintLabel.isHidden = false
        } else {
            hintLabel.isHidden = true
        }
        applyBorder()
    }

    private func updateMessageVisibility() {
        if error != nil { return }
        hintLabel.isHidden = (hintLabel.text ?? "").isEmpty
    }

    // MARK: - Field events

    @objc
    private func handleEditingDidBegin() {
        UIView.animate(withDuration: SPSupport.durationQuick) {
            self.applyBorder()
            // Soft money500 glow on focus — matches `.sp-input:focus`
            // ring in components.css. Skipped while in error state so
            // the pain border keeps its priority.
            self.fieldContainer.layer.shadowOpacity = self.error == nil ? 0.12 : 0
        }
    }

    @objc
    private func handleEditingDidEnd() {
        UIView.animate(withDuration: SPSupport.durationQuick) {
            self.applyBorder()
            self.fieldContainer.layer.shadowOpacity = 0
        }
    }

    @objc
    private func handleEditingChanged() {
        onChange?(textField.text ?? "")
    }
}
