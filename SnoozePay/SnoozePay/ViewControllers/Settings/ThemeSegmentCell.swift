import UIKit

/// Settings row that owns the theme `SPSegmented` selector. Replaces the
/// previous pattern in `SettingsViewController` where a single shared segment
/// instance was repeatedly removed/re-added across cell reuse — fragile, and
/// guaranteed to lose the control to the most-recently-rendered cell.
///
/// V3 (#283): restyled with SP tokens — a bare tinted glyph (no 30×30 chip)
/// + `SPSegmented` instead of the stock `UISegmentedControl` / `info500`
/// look. The segment lives in a second row below the title so the three
/// labels ("Системная / Светлая / Тёмная") have room on narrow screens.
///
/// The cell is configured by the data source via
/// `configure(selectedIndex:onChange:)` and forwards segment events through
/// the closure.
final class ThemeSegmentCell: UITableViewCell {

    static let reuseID = "ThemeSegmentCell"

    /// Stable segment values mapped to the theme preference (index 0/1/2).
    ///
    /// Computed, not a `static let`: a stored one would cache the labels for
    /// the life of the process, giving this copy its own cache on top of the
    /// one `Localized.bundle` already keeps. Same reason #712 dropped the
    /// stored copy it found — after #596 the bundle can change, and
    /// `Localized.bundle` should be the only place that has to notice.
    private static var options: [SPSegmented.Option] {
        [
            .init(value: "system", label: Localized.text("settings.theme.system")),
            .init(value: "light", label: Localized.text("settings.theme.light")),
            .init(value: "dark", label: Localized.text("settings.theme.dark"))
        ]
    }

    // MARK: - UI

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "moon")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        )
        imageView.tintColor = AppColors.fg3
        imageView.contentMode = .center
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("settings.theme.title")
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let segment: SPSegmented = {
        let control = SPSegmented(options: ThemeSegmentCell.options)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    /// Forwarded on every selection change. `Int` index keeps the call site in
    /// `SettingsViewController` unchanged (it maps index → theme).
    private var onChange: ((Int) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        // The brand card surface, not the system grey. `styleAsCardRow` clears
        // this and takes over the fill on every table that hosts the cell, but
        // the system token was the wrong colour in dark (`#1C1C1E` against the
        // card's `#0E1320`) for any host that doesn't (#515).
        backgroundColor = AppColors.bg1
        selectionStyle = .none

        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(segment)

        segment.onChange = { [weak self] value in
            self?.onChange?(Self.index(for: value))
        }

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            iconImageView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: AppSpacing.md),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor,
                constant: -AppSpacing.lg
            ),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.md),

            segment.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            segment.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            segment.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: AppSpacing.sm),
            segment.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.md),
            segment.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    // MARK: - Configure

    /// Set the currently selected segment and the change handler. Safe to call
    /// repeatedly on cell reuse — the previous handler is dropped.
    func configure(selectedIndex: Int, onChange: @escaping (Int) -> Void) {
        segment.selectedValue = Self.value(for: selectedIndex)
        self.onChange = onChange
    }

    // MARK: - Index ↔ value mapping

    private static func value(for index: Int) -> String {
        guard options.indices.contains(index) else { return options[0].value }
        return options[index].value
    }

    private static func index(for value: String) -> Int {
        options.firstIndex { $0.value == value } ?? 0
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        // Drop the previous closure so a recycled cell doesn't fire its old
        // owner's handler before `configure` is called again.
        onChange = nil
    }
}
