import UIKit

/// Settings / list row primitive — `.sp-row` in `components.css`.
///
/// Layout: leading icon (optional) → main column (title + optional
/// subtitle) → trailing accessory (chevron / switch / value label /
/// arbitrary view). Tap target spans the whole row and is gated to ≥44pt
/// to satisfy the iOS HIG minimum.
///
/// SPRows are designed to stack inside an `SPCard` or be used as the
/// content of a UITableViewCell. The `divider` flag draws a 1px hairline
/// across the bottom edge so consecutive rows visually separate without
/// the caller having to add per-row separators.
final class SPRow: UIControl {

    // MARK: - Configuration

    let showsDivider: Bool
    /// Closure invoked on `.touchUpInside`. Storing the callback so the
    /// caller doesn't have to wire `addTarget` boilerplate.
    var onTap: (() -> Void)?

    // MARK: - Subviews

    private let leadingContainer = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let trailingContainer = UIView()
    private let divider = UIView()
    private let mainStack = UIStackView()
    private let textStack = UIStackView()

    // MARK: - Init

    /// - Parameters:
    ///   - title: Primary label (`bodyLg` 17pt medium).
    ///   - subtitle: Optional secondary label (`meta` 13pt medium).
    ///   - leading: Optional leading view (icon, image, badge). Sized via
    ///     its own intrinsic content; rendered in a 24pt-wide column.
    ///   - trailing: Optional trailing view (chevron, switch, value label).
    ///   - divider: When `true` (default) draws a 1px hairline along the
    ///     bottom edge using `stroke1`. The first / last row in a stack
    ///     normally hides this manually.
    ///   - onTap: Tap callback. When set the row paints a faint highlight
    ///     and the system reads it as a button to assistive tech.
    init(
        title: String,
        subtitle: String? = nil,
        leading: UIView? = nil,
        trailing: UIView? = nil,
        divider: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        self.showsDivider = divider
        self.onTap = onTap
        super.init(frame: .zero)
        configure()
        titleLabel.text = title
        if let subtitle = subtitle {
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.isHidden = true
        }
        if let leading = leading {
            install(leading, in: leadingContainer)
            leadingContainer.isHidden = false
        } else {
            leadingContainer.isHidden = true
        }
        if let trailing = trailing {
            install(trailing, in: trailingContainer)
            trailingContainer.isHidden = false
        } else {
            trailingContainer.isHidden = true
        }
        if onTap != nil {
            isAccessibilityElement = true
            accessibilityTraits = .button
            addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        } else {
            isUserInteractionEnabled = false
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Highlight feedback

    override var isHighlighted: Bool {
        didSet {
            // Subtle background highlight so taps register without a full
            // press scale (rows live inside a card, scaling looks weird
            // when neighbours don't move).
            UIView.animate(withDuration: SPSupport.durationQuick) {
                self.backgroundColor = self.isHighlighted
                    ? AppColors.whiteOverlay04
                    : .clear
            }
        }
    }

    // MARK: - Configuration

    private func configure() {
        // Owns its autoresizing flag. This view activates a required
        // `heightAnchor` on ITSELF (below), which cannot coexist with the
        // constraints UIKit synthesises from the `.zero` frame it is born
        // with. A caller who forgets the reset gets no error: the engine pays
        // for the collision out of whatever else is breakable, which in #467
        // was the intrinsic height of the SIBLINGS — they kept their
        // x/y/width and measured 0 tall, and the screen read as blank.
        //
        // Quieter here than in `SPButton`'s `==` case: an unsatisfiable `>=`
        // need not print "Unable to simultaneously satisfy constraints" at
        // all, so the collapsed neighbour is the only symptom. Owning the flag
        // makes forgetting impossible; call sites that still set it are
        // harmlessly redundant (#584).
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .clear

        leadingContainer.translatesAutoresizingMaskIntoConstraints = false
        trailingContainer.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = AppTypography.bodyLg
        titleLabel.textColor = AppColors.fg1
        titleLabel.numberOfLines = 1

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = AppTypography.meta
        subtitleLabel.textColor = AppColors.fg3
        subtitleLabel.numberOfLines = 1

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .horizontal
        mainStack.alignment = .center
        mainStack.spacing = 14    // matches `gap: 14px`
        mainStack.isUserInteractionEnabled = false
        mainStack.addArrangedSubview(leadingContainer)
        mainStack.addArrangedSubview(textStack)
        mainStack.addArrangedSubview(trailingContainer)
        addSubview(mainStack)

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = AppColors.stroke1
        divider.isHidden = !showsDivider
        addSubview(divider)

        NSLayoutConstraint.activate([
            // 14pt vertical padding × 2 + content height. Hit-target floor
            // is enforced via `heightAnchor >= 44`.
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            // 1px hairline — divide by display scale so the line stays a
            // single device pixel on @2x/@3x. `traitCollection.displayScale`
            // is `0` until the view is in a window, so fall back to 2x.
            divider.heightAnchor.constraint(
                equalToConstant: 1.0 / max(traitCollection.displayScale, 2)
            )
        ])
    }

    private func install(_ view: UIView, in container: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    @objc
    private func handleTap() {
        onTap?()
    }
}
