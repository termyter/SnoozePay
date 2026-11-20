import UIKit

/// The icon, title and trailing value of the «Звук» and «Тема» rows (#1111).
/// Up to `.large` they share one line, exactly as before; from XL
/// (`AppTypography.stacksDenseRows`) the value moves under the title and may
/// wrap, because a long name («Bach's Badinerie», «Своя мелодия») no longer
/// fits beside the icon, the title and the chevron of a 375pt card. The icon
/// then follows the title's line instead of the row's middle, as in iOS
/// Settings.
struct DisclosureRowLayout {
    private let value: UILabel
    private let beside: [NSLayoutConstraint]
    private let under: [NSLayoutConstraint]

    /// All four views are already in `contentView`; the icon's leading edge,
    /// its size and the title's leading edge are the caller's.
    init(icon: UIView, title: UILabel, value: UILabel, chevron: UIView, in contentView: UIView) {
        self.value = value
        let gap = AppSpacing.sp2
        beside = [
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            value.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -gap),
            value.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            value.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: gap)
        ]
        // Top-down with an open bottom: a row taller than its text has one
        // place for the slack, not two labels tied for it.
        under = [
            icon.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp3),
            title.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -gap),
            value.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            value.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            value.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -gap),
            value.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -AppSpacing.sp3)
        ]
        // The title is one word: it never wraps, and in a row it is the value
        // that gives way. The chevron never does — no tie with either label.
        title.numberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultHigh + 1, for: .horizontal)
        value.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func apply(_ category: UIContentSizeCategory) {
        let stacked = AppTypography.stacksDenseRows(category)
        NSLayoutConstraint.deactivate(stacked ? beside : under)
        NSLayoutConstraint.activate(stacked ? under : beside)
        value.numberOfLines = stacked ? 0 : 1
    }
}
