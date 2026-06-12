import UIKit
import AudioToolbox

/// Full-screen sound picker pushed onto the navigation stack (V3 — #285).
///
/// Structure per `SPMore.jsx:330-409`:
/// - a single `SPCard` list — each row is a `SoundPickerRowCell` (36×36 icon
///   tile, descriptive subtitle, trailing money checkmark on the selected
///   row), with a disabled «Своя мелодия · скоро» slot pinned at the bottom;
/// - a bottom «Превью» player card with a money-gradient play/pause head that
///   previews the currently-highlighted sound through `previewSound`;
/// - a «Готово» quiet-sm header button. Selection no longer auto-pops — the
///   user leaves via «Готово» or the back chevron.
///
/// `onSelect` / `previewSound` keep their pre-V3 signatures so the alarm form
/// caller doesn't change.
final class SoundPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Properties

    private let sounds: [SoundCatalogue.Entry]
    private var selectedSoundID: String
    private let onSelect: (String) -> Void
    private let previewSound: (String) -> Void

    /// `true` while the «Превью» head is in its "playing" affordance. System
    /// sounds are fire-and-forget, so this is a UI state reset by a timer keyed
    /// to the typical preview length.
    private var isPreviewing = false
    private var previewResetWorkItem: DispatchWorkItem?

    /// The disabled custom-melody slot is appended after the catalogue rows.
    private var rowCount: Int { sounds.count + 1 }

    // MARK: - UI

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alwaysBounceVertical = true
        return view
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp5
        return stack
    }()

    private let listCard: SPCard = {
        let card = SPCard(tone: .surface, padding: 0, cornerRadius: AppRadius.lg)
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .clear
        table.isScrollEnabled = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        // Clip rows to the card's rounded corners (the card itself keeps
        // masksToBounds off for its shadow).
        table.layer.cornerRadius = AppRadius.lg
        table.layer.masksToBounds = true
        return table
    }()

    private let previewCapsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: "Превью".uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        return label
    }()

    private let previewCard: SPCard = {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.md)
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()

    /// 48×48 money-gradient round play/pause head inside the preview card.
    private let previewPlayButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 24
        button.layer.masksToBounds = true
        button.tintColor = AppColors.fgOnMoney
        button.setImage(
            UIImage(systemName: "play.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
        return button
    }()

    private let previewPlayGradient = CAGradientLayer()

    private let previewTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.numberOfLines = 1
        return label
    }()

    private let previewHintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.text = "Нажмите, чтобы прослушать"
        label.numberOfLines = 1
        return label
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - sounds: Available sounds (id + display name + descriptive subtitle).
    ///   - selectedID: Currently selected sound id.
    ///   - onSelect: Fired when the user picks a sound. The picker no longer
    ///     pops itself — the user leaves via «Готово» / back.
    ///   - previewSound: Plays a preview for a given sound id.
    init(
        sounds: [SoundCatalogue.Entry],
        selectedID: String,
        onSelect: @escaping (String) -> Void,
        previewSound: @escaping (String) -> Void
    ) {
        self.sounds = sounds
        self.selectedSoundID = selectedID
        self.onSelect = onSelect
        self.previewSound = previewSound
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
        setupHeader()
        setupContent()
        refreshPreviewLabel()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        previewResetWorkItem?.cancel()
        previewResetWorkItem = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewPlayGradient.frame = previewPlayButton.bounds
    }

    // MARK: - Setup

    private func setupHeader() {
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(
            string: "Звук".uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        titleLabel.accessibilityLabel = "Выбор звука"
        navigationItem.titleView = titleLabel

        // «Готово» quiet-sm — the only way out beyond the back chevron now that
        // selection doesn't auto-pop.
        let doneButton = SPButton(title: "Готово", variant: .quiet, size: .sm)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: doneButton)
    }

    private func setupContent() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SoundPickerRowCell.self, forCellReuseIdentifier: SoundPickerRowCell.reuseID)
        // padding 0 card → pin the table to the card edges; rows draw their
        // own 16pt inset to match the JSX «padding "4px 20px"» list recipe.
        listCard.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: listCard.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: listCard.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: listCard.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: listCard.bottomAnchor)
        ])

        contentStack.addArrangedSubview(listCard)
        contentStack.addArrangedSubview(makePreviewBlock())

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor, constant: AppSpacing.sp5
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: AppSpacing.sp4
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -AppSpacing.sp4
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -AppSpacing.sp5
            ),

            previewPlayButton.widthAnchor.constraint(equalToConstant: 48),
            previewPlayButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        // The table is non-scrolling — drive its height from content so it
        // fits inside the SPCard and the whole screen scrolls as one.
        let tableHeight = tableView.heightAnchor.constraint(equalToConstant: CGFloat(rowCount) * 64)
        tableHeight.priority = .defaultHigh
        tableHeight.isActive = true
        self.tableHeightConstraint = tableHeight
    }

    /// Builds the bottom «Превью» player block (caps label + player card with
    /// money-gradient play head). Kept separate so `setupContent` stays small.
    private func makePreviewBlock() -> UIStackView {
        previewPlayGradient.startPoint = SPSupport.gradientStart
        previewPlayGradient.endPoint = SPSupport.gradientEnd
        previewPlayGradient.colors = SPSupport.moneyGradientColors
        previewPlayGradient.locations = SPSupport.moneyGradientLocations
        previewPlayButton.layer.insertSublayer(previewPlayGradient, at: 0)
        previewPlayButton.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)

        let previewTextStack = UIStackView(arrangedSubviews: [previewTitleLabel, previewHintLabel])
        previewTextStack.translatesAutoresizingMaskIntoConstraints = false
        previewTextStack.axis = .vertical
        previewTextStack.spacing = 2
        previewTextStack.alignment = .leading

        let previewRow = UIStackView(arrangedSubviews: [previewPlayButton, previewTextStack])
        previewRow.translatesAutoresizingMaskIntoConstraints = false
        previewRow.axis = .horizontal
        previewRow.spacing = AppSpacing.sp3
        previewRow.alignment = .center
        previewCard.addSubview(previewRow)
        NSLayoutConstraint.activate([
            previewRow.topAnchor.constraint(equalTo: previewCard.layoutMarginsGuide.topAnchor),
            previewRow.leadingAnchor.constraint(equalTo: previewCard.layoutMarginsGuide.leadingAnchor),
            previewRow.trailingAnchor.constraint(equalTo: previewCard.layoutMarginsGuide.trailingAnchor),
            previewRow.bottomAnchor.constraint(equalTo: previewCard.layoutMarginsGuide.bottomAnchor)
        ])

        let previewBlock = UIStackView(arrangedSubviews: [previewCapsLabel, previewCard])
        previewBlock.translatesAutoresizingMaskIntoConstraints = false
        previewBlock.axis = .vertical
        previewBlock.spacing = AppSpacing.sp2 + 2
        return previewBlock
    }

    private var tableHeightConstraint: NSLayoutConstraint?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Match the SPCard height to the table's laid-out content so no rows
        // are clipped on larger Dynamic Type sizes.
        tableView.layoutIfNeeded()
        tableHeightConstraint?.constant = tableView.contentSize.height
    }

    // MARK: - Table view

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rowCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SoundPickerRowCell.reuseID, for: indexPath
        ) as? SoundPickerRowCell else {
            return UITableViewCell()
        }
        let isLast = indexPath.row == rowCount - 1

        if indexPath.row < sounds.count {
            let sound = sounds[indexPath.row]
            cell.configure(
                name: sound.name,
                subtitle: sound.subtitle,
                isSelected: sound.id == selectedSoundID,
                isLast: isLast,
                isEnabled: true
            )
        } else {
            // Disabled «Своя мелодия · скоро» slot.
            let slot = SoundCatalogue.customSlot
            cell.configure(
                name: "\(slot.name) · скоро",
                subtitle: "Импорт своей мелодии появится позже",
                isSelected: false,
                isLast: isLast,
                isEnabled: false
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < sounds.count else { return } // custom slot is inert
        let sound = sounds[indexPath.row]
        selectedSoundID = sound.id
        onSelect(sound.id)
        // Preview the freshly-picked sound, but DON'T pop — the user stays on
        // the screen and leaves via «Готово».
        previewSound(sound.id)
        startPreviewAffordance(for: sound.id)
        tableView.reloadData()
        refreshPreviewLabel()
    }

    // MARK: - Preview player

    private func refreshPreviewLabel() {
        let name = sounds.first(where: { $0.id == selectedSoundID })?.name ?? selectedSoundID
        previewTitleLabel.text = name
    }

    @objc private func previewTapped() {
        if isPreviewing {
            isPreviewing = false
            previewResetWorkItem?.cancel()
            updatePreviewIcon()
            return
        }
        previewSound(selectedSoundID)
        startPreviewAffordance(for: selectedSoundID)
    }

    /// Flip the preview head to its "playing" state and schedule a reset once
    /// the typical preview length elapses (system sounds can't be stopped).
    private func startPreviewAffordance(for soundID: String) {
        previewResetWorkItem?.cancel()
        isPreviewing = true
        updatePreviewIcon()

        let duration = Self.previewDurationSeconds(for: soundID)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isPreviewing = false
            self.updatePreviewIcon()
        }
        previewResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func updatePreviewIcon() {
        let symbol = isPreviewing ? "pause.fill" : "play.fill"
        previewPlayButton.setImage(
            UIImage(systemName: symbol)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
    }

    @objc private func doneTapped() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Preview duration metadata

    /// Approximate preview length per sound id — drives the visual reset timer.
    private static let previewDurations: [String: Double] = [
        "dawn": 6, "radar": 4, "drops": 2, "piano": 3, "guitar": 3,
        "bell": 2, "waves": 8, "birds": 6, "classic": 5, "jazz": 5
    ]

    private static func previewDurationSeconds(for soundID: String) -> Double {
        previewDurations[soundID] ?? 3
    }
}

// `SoundPickerRowCell` lives in
// `ViewControllers/Alarms/Cells/SoundPickerRowCell.swift`.
