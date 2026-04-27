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
        /// Trailing "+ Своё фото" tile. Distinct case so the cell can render
        /// the placeholder iconography even when no custom image is picked.
        case customSlot
    }

    // MARK: - UI

    private var collectionView: UICollectionView!

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
        title = "Тема"
        view.backgroundColor = AppColors.bg0
        setupCollectionView()
    }

    // MARK: - Setup

    private func setupCollectionView() {
        let layout = makeLayout()
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.dataSource = self
        view.delegate = self
        view.register(AlarmThemeTileCell.self, forCellWithReuseIdentifier: AlarmThemeTileCell.reuseID)
        self.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        self.collectionView = view
    }

    /// Two-column compositional grid. Item ratio is 16:9 — width is whatever
    /// the column resolves to, height tracks via `.fractionalWidth(9.0/16.0)`
    /// on the group, dropped to ~`0.625` to leave room for the in-tile name
    /// label without forcing a separate sectional header layout.
    private func makeLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.5),
            heightDimension: .fractionalHeight(1.0)
        ))
        item.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: 0, bottom: 0, trailing: AppSpacing.sp3
        )

        // Group height = (9/16) * group-width. Group width ≈ available width
        // after content insets; each row contains 2 items.
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalWidth(0.5 * (9.0 / 16.0) + 0.06)
            ),
            subitems: [item]
        )
        group.interItemSpacing = .fixed(0)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: AppSpacing.sp4,
            leading: AppSpacing.sp4,
            bottom: AppSpacing.sp4,
            trailing: AppSpacing.sp4 - AppSpacing.sp3 // trailing inset already on items
        )
        section.interGroupSpacing = AppSpacing.sp3

        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - Selection

    /// Apply the selection and pop back. Built-in themes commit immediately;
    /// `.custom` routes through the photo picker first.
    private func selectItem(at indexPath: IndexPath) {
        switch items[indexPath.item] {
        case .theme(let theme):
            currentTheme = theme
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
            title: "Не удалось сохранить фото",
            message: "Попробуйте выбрать другое изображение.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Tile cell
// `AlarmThemeTileCell` lives in its own file under
// `ViewControllers/Alarms/Cells/` so this file stays under the SwiftLint
// `file_length` cap. The picker is the only consumer.
