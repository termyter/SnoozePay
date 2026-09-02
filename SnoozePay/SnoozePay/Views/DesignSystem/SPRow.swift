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
    /// Held so `layoutSubviews` can swap the provisional hairline for the one
    /// the row's actual screen calls for.
    private var dividerHeightConstraint: NSLayoutConstraint?

    // MARK: - Init

    /// - Parameters:
    ///   - title: Primary label (`bodyLg` 17pt medium).
    ///   - subtitle: Optional secondary label (`meta` 13pt medium).
    ///   - leading: Optional leading view (icon, image, badge). Sized via
    ///     its own intrinsic content; rendered in a 24pt-wide column.
    ///   - trailing: Optional trailing view (chevron, switch, value label).
    ///   - titleLines: How many lines the title may wrap onto. Defaults to 1.
    ///     That default is the app's, NOT the canon's: `.sp-row__title`
    ///     (`components.css:97`) sets no `white-space` and no clamp, and
    ///     `.sp-row__main` (`:96`) is `flex: 1; min-width: 0`, so the
    ///     prototype's title wraps to as many lines as it needs. The only
    ///     `nowrap` rules in that file are `:13` (`.sp-btn`) and `:126`
    ///     (`.sp-preset__pop`). 1 is a deliberate tightening — it keeps a
    ///     list's rows on one rhythm — and `titleLines: 2` is therefore a step
    ///     back TOWARDS canon, not away from it.
    ///
    ///     Pass 2 where the row's own copy is longer than the run the layout
    ///     can give it — the wallet's «Возврат за откладывание» needs 210pt
    ///     and the widest phone can spare 210pt only with a zero card inset
    ///     (#677). A truncated title is worse than a two-storey one: the
    ///     amount beside it stays put either way, and the ellipsis eats the
    ///     noun that says WHAT the money did.
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
        titleLines: Int = 1,
        divider: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        self.showsDivider = divider
        self.onTap = onTap
        super.init(frame: .zero)
        configure()
        titleLabel.numberOfLines = titleLines
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
        // Overwritten from `init` by `titleLines`. 1 is the app's default,
        // not the prototype's — see the `titleLines` parameter doc.
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

        // `configure()` runs from `init`, so the row has neither a superview
        // nor a window here and its scale is not knowable yet. Build the
        // divider at the provisional width — never thicker than a real
        // hairline — and re-read it in `layoutSubviews` once there is a screen
        // to ask. Freezing a full point here is the failure that matters: on a
        // screenshot 1pt is indistinguishable from a divider somebody drew on
        // purpose, so the defect reads as intent.
        let dividerHeight = divider.heightAnchor.constraint(
            equalToConstant: AppHairline.provisionalWidth
        )
        dividerHeightConstraint = dividerHeight

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
            dividerHeight
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // No `window != nil` guard: `testADetachedView_reportsTheSameScaleAsAHostedOne`
        // pins that a view outside a window still reports its screen's scale,
        // so there is a real number to read here and `AppHairline.width(for:)`
        // will not hit its degenerate branch. Guarding would leave the
        // provisional width frozen with no log and no assertion — the exact
        // thing `provisionalWidth`'s own docstring calls a wrong value with a
        // nicer name. Written only on change, so laying out never re-dirties
        // the engine.
        guard let dividerHeight = dividerHeightConstraint else { return }
        let width = hairlineWidth
        if dividerHeight.constant != width {
            dividerHeight.constant = width
        }
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
