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

    /// Per-alarm volume + fade-in, surfaced via a «Громкость» row that pushes
    /// `VolumePickerViewController` (#270 — option 2: sound + volume are
    /// cohesive, so the volume entry point lives on the sound screen rather
    /// than the create/edit settings card). Kept in sync as the user edits.
    private var volume: Float
    private var fadeIn: Bool
    /// Fired live as the volume/fade-in picker reports changes, so the caller
    /// can persist. `nil` when the host doesn't surface volume control.
    private let onVolumeChange: ((Float, Bool) -> Void)?

    /// `true` while the «Превью» head is in its "playing" affordance. System
    /// sounds are fire-and-forget, so this is a UI state reset by a timer keyed
    /// to the typical preview length.
    private var isPreviewing = false

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

    /// Progress track + fill + timecode, per `SPMore.jsx:358-363` — a 3pt
    /// white-08 rail with a money-gradient fill and a «0:08 / 0:24» meta label.
    /// The fill is driven by a `CADisplayLink` keyed to the sound's expected
    /// preview length (system sounds are fire-and-forget, so the bar reflects
    /// elapsed-vs-expected rather than true decoder position).
    private let progressTrack: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.whiteOverlay08
        view.layer.cornerRadius = 1.5
        view.layer.masksToBounds = true
        return view
    }()

    /// Money-gradient fill. `GradientRailFill` sizes its gradient in its own
    /// `layoutSubviews`, so the colour always tracks the view's bounds with no
    /// dependency on the view controller's layout timing.
    private let progressFill = GradientRailFill()

    private let timecodeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 1
        return label
    }()

    /// Width of the filled portion of the progress rail. Animated to `0…track`
    /// each `CADisplayLink` tick; `0` while idle.
    private var progressFillWidth: NSLayoutConstraint?

    /// Trailing value label on the «Громкость» row — reads e.g. «80% · плавно».
    /// Refreshed when the volume picker reports a change.
    private let volumeValueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg3
        label.textAlignment = .right
        return label
    }()

    /// Drives the progress fill + timecode during a preview. Nil while idle.
    private var progressLink: CADisplayLink?
    /// Host time (`CACurrentMediaTime`) at which the current preview started.
    private var previewStartTime: CFTimeInterval = 0
    /// Expected length of the in-flight preview, in seconds.
    private var previewTotalDuration: Double = 0

    // MARK: - Init

    /// - Parameters:
    ///   - sounds: Available sounds (id + display name + descriptive subtitle).
    ///   - selectedID: Currently selected sound id.
    ///   - onSelect: Fired when the user picks a sound. The picker no longer
    ///     pops itself — the user leaves via «Готово» / back.
    ///   - previewSound: Plays a preview for a given sound id.
    ///   - volume: Initial per-alarm volume in `0.0...1.0`. Drives the
    ///     «Громкость» row value; defaults to full volume.
    ///   - fadeIn: Initial fade-in flag for the «Громкость» row.
    ///   - onVolumeChange: Fired live as the pushed `VolumePickerViewController`
    ///     reports slider / switch changes. Pass `nil` to hide the volume row.
    init(
        sounds: [SoundCatalogue.Entry],
        selectedID: String,
        onSelect: @escaping (String) -> Void,
        previewSound: @escaping (String) -> Void,
        volume: Float = 1.0,
        fadeIn: Bool = false,
        onVolumeChange: ((Float, Bool) -> Void)? = nil
    ) {
        self.sounds = sounds
        self.selectedSoundID = selectedID
        self.onSelect = onSelect
        self.previewSound = previewSound
        // Clamp the seed so a corrupt persisted volume can't render «-12%».
        self.volume = min(max(volume.isFinite ? volume : 1.0, 0), 1)
        self.fadeIn = fadeIn
        self.onVolumeChange = onVolumeChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Defence in depth: `CADisplayLink` holds a strong target ref, so a
        // teardown that skips `viewWillDisappear` would otherwise keep the link
        // (and this VC) alive and ticking. Normal exits already invalidate it.
        progressLink?.invalidate()
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
        stopPreview()
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
        // «Громкость» entry point — only when the host wired up a change
        // handler (#270). Restores the volume/fade-in picker dropped by the
        // 3-row settings card in #263.
        if onVolumeChange != nil {
            contentStack.addArrangedSubview(makeVolumeBlock())
            refreshVolumeLabel()
        }

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
        previewPlayButton.accessibilityLabel = "Прослушать превью"

        progressTrack.addSubview(progressFill)

        let fillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidth = fillWidth
        NSLayoutConstraint.activate([
            progressTrack.heightAnchor.constraint(equalToConstant: 3),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fillWidth
        ])

        let previewTextStack = UIStackView(arrangedSubviews: [progressTrack, timecodeLabel])
        previewTextStack.translatesAutoresizingMaskIntoConstraints = false
        previewTextStack.axis = .vertical
        previewTextStack.spacing = AppSpacing.sp1 + 2   // 6pt — matches `marginTop: 6`
        previewTextStack.alignment = .fill

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

    /// Resets the rail + timecode to the at-rest «0:00 / total» state for the
    /// currently-selected sound. Called when the selection changes so the total
    /// reflects the new sound's expected length.
    private func refreshPreviewLabel() {
        resetProgress()
    }

    @objc private func previewTapped() {
        if isPreviewing {
            stopPreview()
            return
        }
        previewSound(selectedSoundID)
        startPreviewAffordance(for: selectedSoundID)
    }

    /// Flip the preview head to its "playing" state and start the progress
    /// rail. System sounds are fire-and-forget, so the rail/timecode track the
    /// expected preview length rather than a real decoder position; a second
    /// tap stops and resets.
    private func startPreviewAffordance(for soundID: String) {
        isPreviewing = true
        previewTotalDuration = Self.previewDurationSeconds(for: soundID)
        previewStartTime = CACurrentMediaTime()
        updatePreviewIcon()

        progressLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tickProgress))
        link.add(to: .main, forMode: .common)
        progressLink = link
        // Resolve the rail width before the first synchronous tick so frame 0
        // paints the correct fraction instead of a transient empty bar.
        view.layoutIfNeeded()
        tickProgress()
    }

    /// Stops an in-flight preview (second tap or screen leaving) and snaps the
    /// rail back to empty. The underlying system sound can't be cancelled, but
    /// the affordance must reflect "not playing".
    private func stopPreview() {
        isPreviewing = false
        progressLink?.invalidate()
        progressLink = nil
        updatePreviewIcon()
        resetProgress()
    }

    @objc private func tickProgress() {
        let elapsed = CACurrentMediaTime() - previewStartTime
        let total = max(previewTotalDuration, 0.001)
        let fraction = min(1, max(0, elapsed / total))
        setProgress(fraction: fraction, elapsed: min(elapsed, total), total: total)

        if fraction >= 1 {
            // Preview elapsed — drop back to the idle play affordance.
            isPreviewing = false
            progressLink?.invalidate()
            progressLink = nil
            updatePreviewIcon()
        }
    }

    private func setProgress(fraction: Double, elapsed: Double, total: Double) {
        progressFillWidth?.constant = progressTrack.bounds.width * CGFloat(fraction)
        timecodeLabel.text = "\(Self.timecode(elapsed)) / \(Self.timecode(total))"
    }

    /// Snaps the rail to empty and the timecode to «0:00 / total» for the
    /// selected sound.
    private func resetProgress() {
        let total = Self.previewDurationSeconds(for: selectedSoundID)
        progressFillWidth?.constant = 0
        timecodeLabel.text = "\(Self.timecode(0)) / \(Self.timecode(total))"
    }

    private func updatePreviewIcon() {
        let symbol = isPreviewing ? "pause.fill" : "play.fill"
        previewPlayButton.setImage(
            UIImage(systemName: symbol)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
    }

    /// «M:SS» timecode. Negative inputs are clamped to 0 so an out-of-order
    /// clock read can never render malformed «0:-3» text.
    private static func timecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
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

// MARK: - Volume entry point (#270)

/// The «Громкость» entry that PR #263 dropped from the create/edit settings
/// card lives here instead — sound + volume are cohesive, so the volume/fade-in
/// picker is reached from the sound screen (issue #270, option 2).
extension SoundPickerViewController {

    /// Builds the «Громкость» caps label + a single-row `SPCard` whose row
    /// pushes `VolumePickerViewController`. Mirrors the sound-list card recipe
    /// (padding-0 card + inset row) so the entry reads as a sibling of the
    /// sound list.
    func makeVolumeBlock() -> UIStackView {
        let capsLabel = UILabel()
        capsLabel.translatesAutoresizingMaskIntoConstraints = false
        capsLabel.attributedText = NSAttributedString(
            string: "Громкость".uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
        chevron.tintColor = AppColors.fg3
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let trailingStack = UIStackView(arrangedSubviews: [volumeValueLabel, chevron])
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = AppSpacing.sp2

        let row = SPRow(
            title: "Громкость и нарастание",
            trailing: trailingStack,
            divider: false
        ) { [weak self] in
            self?.showVolumePicker()
        }
        row.accessibilityLabel = "Громкость и нарастание"
        row.translatesAutoresizingMaskIntoConstraints = false

        let card = SPCard(tone: .surface, padding: 0, cornerRadius: AppRadius.lg)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            // 20pt horizontal inset to match the JSX «padding "4px 20px"» list
            // recipe used by the sound rows.
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.sp5),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.sp5),
            row.topAnchor.constraint(equalTo: card.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        let block = UIStackView(arrangedSubviews: [capsLabel, card])
        block.translatesAutoresizingMaskIntoConstraints = false
        block.axis = .vertical
        block.spacing = AppSpacing.sp2 + 2
        return block
    }

    /// Refreshes the «Громкость» row value label, e.g. «80% · плавно».
    func refreshVolumeLabel() {
        let percent = "\(Int((volume * 100).rounded()))%"
        volumeValueLabel.text = fadeIn ? "\(percent) · плавно" : percent
    }

    /// Pushes the existing `VolumePickerViewController` (#150) and forwards its
    /// live slider / switch changes to both the local label and the host.
    private func showVolumePicker() {
        let picker = VolumePickerViewController(
            volume: volume,
            fadeIn: fadeIn
        ) { [weak self] newVolume, newFadeIn in
            guard let self else { return }
            self.volume = newVolume
            self.fadeIn = newFadeIn
            self.refreshVolumeLabel()
            self.onVolumeChange?(newVolume, newFadeIn)
        }
        navigationController?.pushViewController(picker, animated: true)
    }
}

/// Money-gradient progress fill that sizes its own gradient in `layoutSubviews`,
/// so the colour always fills the view's current bounds with no dependency on
/// the host view controller's layout timing (silent-failure-hunter, PR #367).
private final class GradientRailFill: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.masksToBounds = true
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.colors = SPSupport.moneyGradientColors
        gradient.locations = SPSupport.moneyGradientLocations
        layer.addSublayer(gradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

// `SoundPickerRowCell` lives in
// `ViewControllers/Alarms/Cells/SoundPickerRowCell.swift`.
