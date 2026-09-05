import UIKit
import PhotosUI

/// Push-navigation grid picker for `AlarmTheme` (#151).
///
/// Layout: 2-column compositional grid, screen inset 16pt, item spacing 12pt,
/// each tile is a 16:9 SPCard surface previewing the theme's gradient/photo
/// with a uppercased name + checkmark when selected. The trailing tile is a
/// `+ Своё фото` affordance that presents `PHPickerViewController`; the
/// returned image is persisted via `AlarmThemeImageStore` and surfaced to the
/// caller via `onSelect`.
///
/// The VC owns no business state — the caller passes in the current selection
/// and provides an `onSelect` callback. Going back via the navigation chevron
/// without picking is treated as cancel.
final class AlarmThemePickerViewController: UIViewController {

    // MARK: - Inputs

    private var currentTheme: AlarmTheme
    private let onSelect: (AlarmTheme) -> Void

    /// Items rendered in the grid. Built-in themes first, custom slot last.
    /// Resolved on init so reordering the static `AlarmTheme.builtInOrder`
    /// list automatically reflects in the picker without further wiring.
    private let items: [Item]

    private enum Item {
        case theme(AlarmTheme)
        /// Trailing «+ Своё фото» tile. Distinct case so the cell can render
        /// the placeholder iconography even when no custom image is picked.
        case customSlot
    }

    // MARK: - UI

    private var collectionView: UICollectionView!

    /// V2 firing-screen preview block — sits above the grid and tracks the
    /// currently-selected theme so the user sees a 180pt-tall stamp of what
    /// the alarm-firing screen will look like before they pick. Matches
    /// `SPMore2.jsx` lines 274-285.
    private let previewContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.lg
        view.layer.masksToBounds = true
        return view
    }()

    /// Theme miniature inside the preview block — identical recipe to the grid
    /// tiles (base gradient + bottom accent glow), so "what I tapped" and
    /// "what I'll wake up to" are the same picture (#463).
    private let previewThemeView = SPThemePreviewView()

    private let previewImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    private let previewClockLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "07:00"
        label.font = AppFonts.mono(.ultralight, 56)
        label.textColor = .white
        label.textAlignment = .center
        // Subtle shadow so the clock stays legible against any gradient stop.
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.4
        label.layer.shadowOffset = .zero
        label.layer.shadowRadius = 8
        return label
    }()

    private let previewCapsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: Localized.text("create_alarm.theme_picker.preview_caps"),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        return label
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - currentTheme: Theme to surface as selected when the grid first
    ///     appears. The caller usually pulls this from the view-model.
    ///   - onSelect: Invoked with the chosen theme. For `.custom` this fires
    ///     after the user has both confirmed in PHPicker AND we've persisted
    ///     the image to disk — never on cancel.
    init(currentTheme: AlarmTheme, onSelect: @escaping (AlarmTheme) -> Void) {
        self.currentTheme = currentTheme
        self.onSelect = onSelect
        var built: [Item] = AlarmTheme.builtInOrder.map { .theme($0) }
        built.append(.customSlot)
        self.items = built
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        // V2 caps title — matches `SPMore2.jsx` lines 269 recipe.
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(
            string: Localized.text("create_alarm.theme_picker.title").uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        titleLabel.accessibilityLabel = Localized.text("create_alarm.theme_picker.title")
        navigationItem.titleView = titleLabel

        // «Готово» quiet-sm — V3 exit affordance, matching the canon header at
        // `docs/design/snoozepay-2026-04-27/project/components/SPMore2.jsx:340`.
        // The path matters: a second copy of that file under
        // `docs/design/v2-handoff/` is numbered differently, and the reference
        // this replaces was reading it.
        //
        // Wrapped so the iOS 26 shared glass capsule stays off it (#666): the
        // canon header is a bare quiet pill, and the capsule would draw a
        // second ring around a control that already carries its own
        // `--sp-white-06` fill. Same call the alarm form and the sound picker
        // make — see `AppNavigationBarStyle.barItem(for:)`.
        let doneButton = SPButton(
            title: Localized.text("common.button.done"), variant: .quiet, size: .sm
        )
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        navigationItem.rightBarButtonItem = AppNavigationBarStyle.barItem(for: doneButton)

        setupCollectionView()
    }

    @objc private func doneTapped() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Setup

    private func setupCollectionView() {
        // V2: preview block + grid, stacked vertically. The preview reflects
        // the live `currentTheme` so the user gets a 180pt-tall sample of
        // the firing screen as they cycle through tiles below.
        previewContainer.addSubview(previewThemeView)
        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(previewClockLabel)

        view.addSubview(previewCapsLabel)
        view.addSubview(previewContainer)

        let layout = makeLayout()
        let grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.backgroundColor = .clear
        grid.alwaysBounceVertical = true
        grid.dataSource = self
        grid.delegate = self
        grid.register(AlarmThemeTileCell.self, forCellWithReuseIdentifier: AlarmThemeTileCell.reuseID)
        grid.register(
            ThemeSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: ThemeSectionHeaderView.reuseID
        )
        self.view.addSubview(grid)

        NSLayoutConstraint.activate([
            previewCapsLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AppSpacing.sp4
            ),
            previewCapsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp4),
            previewCapsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp4),

            previewContainer.topAnchor.constraint(equalTo: previewCapsLabel.bottomAnchor, constant: AppSpacing.sp2),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp4),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp4),
            previewContainer.heightAnchor.constraint(equalToConstant: 180),

            previewThemeView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewThemeView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewThemeView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewThemeView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            previewClockLabel.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            previewClockLabel.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),

            grid.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: AppSpacing.sp3),
            grid.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        self.collectionView = grid
        renderPreview(for: currentTheme)
    }

    /// Re-render the preview block with the given theme's gradient or photo.
    /// Called once on setup and again every time the user taps a tile.
    private func renderPreview(for theme: AlarmTheme) {
        previewImageView.image = nil
        previewImageView.isHidden = true

        if case .custom(let url) = theme, let image = AlarmThemeImageStore.loadImage(at: url) {
            previewImageView.image = image
            previewImageView.isHidden = false
            previewThemeView.isHidden = true
            return
        }

        // `.custom` whose file is gone resolves to no gradient — fall back to
        // Dawn so the block is never an empty hole, matching what the firing
        // screen does in the same situation.
        if !previewThemeView.apply(theme: theme) {
            previewThemeView.apply(theme: .dawn)
        }
    }

    /// Three-column compositional grid, tile aspect 1:1.2 (V3 — SPMore2.jsx:
    /// 430-436). The 10pt inter-column gap is folded into per-item trailing
    /// insets; the row group height tracks the tile aspect so tiles stay 1:1.2.
    /// A «Готовые темы» caps header sits above the grid.
    private func makeLayout() -> UICollectionViewLayout {
        let columns: CGFloat = 3
        let gap = AppSpacing.sp2 + 2 // ≈10pt
        // Approximate fraction the gap takes per row so the tile width/height
        // ratio stays close to 1:1.2 across device widths.
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / columns),
            heightDimension: .fractionalHeight(1.0)
        ))
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: gap)

        // Tile height ≈ tileWidth * 1.2. tileWidth ≈ (groupWidth / 3). Express
        // the group height as a fraction of group width: (1/3) * 1.2.
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalWidth((1.0 / columns) * 1.2)
            ),
            subitems: [item]
        )
        group.interItemSpacing = .fixed(0)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: AppSpacing.sp3,
            leading: AppSpacing.sp4,
            bottom: AppSpacing.sp4,
            trailing: AppSpacing.sp4 - gap // trailing gap already on the last item
        )
        section.interGroupSpacing = gap

        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(28)
            ),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]

        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - Selection

    /// Apply the selection and pop back. Built-in themes commit immediately;
    /// `.custom` routes through the photo picker first. The preview block
    /// refreshes inline so the user sees the firing-screen sample update
    /// before the pop animation completes.
    private func selectItem(at indexPath: IndexPath) {
        switch items[indexPath.item] {
        case .theme(let theme):
            currentTheme = theme
            renderPreview(for: theme)
            onSelect(theme)
            navigationController?.popViewController(animated: true)
        case .customSlot:
            presentPhotoPicker()
        }
    }

    private func presentPhotoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Helpers

    private func isSelected(_ item: Item) -> Bool {
        switch (item, currentTheme) {
        case (.theme(let lhs), let rhs):
            return lhs.id == rhs.id && lhs.id != "custom"
        case (.customSlot, .custom):
            return true
        case (.customSlot, _):
            return false
        }
    }
}

// MARK: - UICollectionViewDataSource / Delegate

extension AlarmThemePickerViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AlarmThemeTileCell.reuseID,
            for: indexPath
        ) as? AlarmThemeTileCell else {
            assertionFailure("dequeue returned wrong type for AlarmThemeTileCell")
            return UICollectionViewCell()
        }
        let item = items[indexPath.item]
        switch item {
        case .theme(let theme):
            cell.configure(theme: theme, isCustomSlot: false, isSelected: isSelected(item), customImage: nil)
        case .customSlot:
            // The slot tile previews the latest custom image (if the user
            // already picked one) so they can tell which photo is currently
            // applied without re-entering PHPicker.
            let image = AlarmThemeRendering.customImage(for: currentTheme)
            cell.configure(theme: .dawn, isCustomSlot: true, isSelected: isSelected(item), customImage: image)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        selectItem(at: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: ThemeSectionHeaderView.reuseID,
            for: indexPath
        ) as? ThemeSectionHeaderView else {
            return UICollectionReusableView()
        }
        header.setTitle(Localized.text("create_alarm.theme_picker.section_presets"))
        return header
    }
}

// MARK: - Section header

/// Caps section header «Готовые темы» above the theme grid (#285).
private final class ThemeSectionHeaderView: UICollectionReusableView {

    static let reuseID = "ThemeSectionHeaderView"

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.sp4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.sp4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sp2)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String) {
        label.attributedText = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
    }
}

// MARK: - PHPickerViewControllerDelegate

extension AlarmThemePickerViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        let provider = result.itemProvider
        guard provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self, let image = object as? UIImage else { return }
            DispatchQueue.main.async {
                guard let url = AlarmThemeImageStore.saveImage(image) else {
                    // Keep the picker on screen — selection didn't happen.
                    self.presentSaveFailureAlert()
                    return
                }
                let theme = AlarmTheme.custom(imagePath: url)
                self.currentTheme = theme
                self.onSelect(theme)
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    private func presentSaveFailureAlert() {
        let alert = UIAlertController(
            title: Localized.text("create_alarm.theme_picker.error.title"),
            message: Localized.text("create_alarm.theme_picker.error.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Localized.text("common.button.ok"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Tile cell
// `AlarmThemeTileCell` lives in its own file under
// `ViewControllers/Alarms/Cells/` so this file stays under the SwiftLint
// `file_length` cap. The picker is the only consumer.
