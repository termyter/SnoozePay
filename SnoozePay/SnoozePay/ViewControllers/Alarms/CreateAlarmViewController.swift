import UIKit

/// Screen for creating or editing an alarm.
/// Each section is rendered by a dedicated `UITableViewCell` subclass that owns
/// its own controls — the previous shared-property design (timePicker,
/// nameField, sliders, toggles…) caused stale-constraint crashes during
/// `reloadSections`, since the same control was re-parented across recycled
/// cells.
final class CreateAlarmViewController: UIViewController {

    // MARK: - Callbacks

    var onSave: (() -> Void)?
    /// Invoked after the user confirms deletion of the alarm being edited so the
    /// presenter can refresh its list. Defaults to nil for new alarms (delete row
    /// is hidden in create mode).
    var onDelete: (() -> Void)?

    // MARK: - Dependencies

    private let viewModel: CreateAlarmViewModel

    // MARK: - UI

    private let tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .insetGrouped)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Sections

    /// Section order matches the #143 PM spec: name first (auto-focus on
    /// create), then time picker, repeat days, snooze slider, penalty,
    /// progressive scale, sound, vibration, theme, and finally the
    /// destructive delete action (edit-mode only).
    private enum Section: Int, CaseIterable {
        case name = 0
        case timePicker
        case repeatDays
        case snoozeTime
        case penalty
        case progressiveScale
        case sound
        case volume
        case vibration
        case theme
        /// Destructive "Удалить будильник" row — only visible in edit mode.
        case deleteAction
    }

    // MARK: - Init

    init(alarm: Alarm?) {
        self.viewModel = CreateAlarmViewModel(alarm: alarm)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.isEditing ? "Редактировать" : "Новый будильник"
        view.backgroundColor = .systemGroupedBackground
        setupNavigationBar()
        setupTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh the sound + volume + theme rows in case the user picked a
        // new value on a pushed picker and is returning here.
        tableView.reloadSections(
            IndexSet([Section.sound.rawValue, Section.volume.rawValue, Section.theme.rawValue]),
            with: .none
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Auto-focus the name field on create so the user can start typing
        // immediately (matches iOS Reminders' "tap +" UX, #143). Edit mode
        // skips this so the user isn't slammed with the keyboard when they
        // just want to tweak the time / penalty.
        guard !viewModel.isEditing, !didAutoFocusName else { return }
        didAutoFocusName = true
        let nameIndexPath = IndexPath(row: 0, section: Section.name.rawValue)
        if let cell = tableView.cellForRow(at: nameIndexPath) as? NameCell {
            cell.beginEditing()
        }
    }

    /// Guards `viewDidAppear`'s auto-focus from re-firing on every return
    /// from a pushed picker (Sound, Theme).
    private var didAutoFocusName = false

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Сохранить",
            style: .plain,
            target: self,
            action: #selector(saveTapped)
        )
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TimePickerCell.self, forCellReuseIdentifier: TimePickerCell.reuseID)
        tableView.register(DayPickerCell.self, forCellReuseIdentifier: DayPickerCell.reuseID)
        tableView.register(NameCell.self, forCellReuseIdentifier: NameCell.reuseID)
        tableView.register(SoundCell.self, forCellReuseIdentifier: SoundCell.reuseID)
        tableView.register(VolumeCell.self, forCellReuseIdentifier: VolumeCell.reuseID)
        tableView.register(VibrationCell.self, forCellReuseIdentifier: VibrationCell.reuseID)
        tableView.register(PenaltyCell.self, forCellReuseIdentifier: PenaltyCell.reuseID)
        tableView.register(ProgressiveScaleCell.self, forCellReuseIdentifier: ProgressiveScaleCell.reuseID)
        tableView.register(ProgressivePreviewCell.self, forCellReuseIdentifier: ProgressivePreviewCell.reuseID)
        tableView.register(SnoozeSliderCell.self, forCellReuseIdentifier: SnoozeSliderCell.reuseID)
        tableView.register(ThemeRowCell.self, forCellReuseIdentifier: ThemeRowCell.reuseID)
        tableView.register(DeleteActionCell.self, forCellReuseIdentifier: DeleteActionCell.reuseID)

        // Pin to safe area on top so the first section's "ПОВТОР" header is
        // not clipped under the navigation bar.
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        // Cells push state into the view-model live via callbacks, so save just
        // forwards the current snapshot to the repository.
        // The async overload waits on `AlarmScheduler.schedule` to resolve so
        // we don't dismiss-and-toast on a notification request that
        // silently failed to register (issue #118).
        viewModel.save { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success:
                self.onSave?()
                self.dismiss(animated: true)
            case .persistFailed:
                // Persist failed (corrupt store / encode error). Surface the
                // failure inline so the user doesn't tap "Сохранить", see the
                // sheet dismiss, and assume their alarm landed (issue #72).
                self.presentSaveError(
                    title: "Не удалось сохранить",
                    error: AlarmRepository.RepositoryError.persistBlocked
                )
            case .schedulingFailed(let error):
                // Persist landed but the notification didn't — the user is
                // about to go to bed thinking the alarm will ring. Tell
                // them so they can fix the cause (issue #118).
                self.presentSaveError(
                    title: "Не удалось запланировать будильник",
                    error: error
                )
            }
        }
    }

    /// Inline alert for repository or scheduler failures that block the
    /// save flow. Kept generic so the same call site can present any
    /// `LocalizedError` (issues #72, #118).
    private func presentSaveError(title: String, error: LocalizedError) {
        let alert = UIAlertController(
            title: title,
            message: error.errorDescription ?? "Попробуйте ещё раз.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - View-model bridges

    private func setProgressiveScale(_ isOn: Bool) {
        viewModel.progressiveScale = isOn

        guard view.window != nil else {
            // Detached views can't safely run insertRows/deleteRows; reload as a
            // safe fallback (no animation visible to the user anyway).
            tableView.reloadSections(IndexSet(integer: Section.progressiveScale.rawValue), with: .none)
            return
        }

        let previewIndexPath = IndexPath(row: 1, section: Section.progressiveScale.rawValue)
        tableView.performBatchUpdates({
            if isOn {
                tableView.insertRows(at: [previewIndexPath], with: .fade)
            } else {
                tableView.deleteRows(at: [previewIndexPath], with: .fade)
            }
        })
    }

    private func setPenaltyAmount(_ amount: Double) {
        viewModel.penaltyAmount = amount
        // Refresh the preview row's text if it's currently visible.
        guard viewModel.progressiveScale else { return }
        let previewIndexPath = IndexPath(row: 1, section: Section.progressiveScale.rawValue)
        if let cell = tableView.cellForRow(at: previewIndexPath) as? ProgressivePreviewCell {
            cell.configure(text: viewModel.progressiveScalePreview)
        }
    }
}

// MARK: - UITableViewDataSource

extension CreateAlarmViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .progressiveScale:
            return viewModel.progressiveScale ? 2 : 1
        case .deleteAction:
            return viewModel.isEditing ? 1 : 0
        default:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .repeatDays: return "ПОВТОР"
        case .sound: return "ЗВУК"
        case .penalty: return "ШТРАФ ЗА ОТКЛАДЫВАНИЕ"
        case .snoozeTime: return "ВРЕМЯ ОТКЛАДЫВАНИЯ"
        case .theme: return "ОФОРМЛЕНИЕ"
        // Name no longer carries a header — the large in-cell placeholder
        // already reads as the field's purpose (#143).
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // Custom header view so each section uses the design-system caps
        // role + tracking instead of the system's default footnote font.
        // Falling through to the default `titleForHeaderInSection` keeps
        // accessibility (`accessibilityLabel`) intact.
        guard let title = self.tableView(tableView, titleForHeaderInSection: section) else {
            return nil
        }
        return SectionHeaderView(text: title)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard self.tableView(tableView, titleForHeaderInSection: section) != nil else {
            return .leastNonzeroMagnitude
        }
        // Match the system's default grouped section header height so the
        // custom typography swap doesn't shift the form's vertical rhythm.
        return UITableView.automaticDimension
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch section {
        case .timePicker:
            let cell = tableView.dequeueReusableCell(withIdentifier: TimePickerCell.reuseID, for: indexPath)
            if let cell = cell as? TimePickerCell {
                cell.configure(time: viewModel.time)
                cell.onTimeChanged = { [weak self] date in self?.viewModel.time = date }
            }
            return cell
        case .repeatDays:
            let cell = tableView.dequeueReusableCell(withIdentifier: DayPickerCell.reuseID, for: indexPath)
            if let cell = cell as? DayPickerCell {
                cell.configure(selectedDays: viewModel.repeatDays)
                cell.onDayToggled = { [weak self, weak cell] day in
                    guard let self else { return }
                    self.viewModel.toggleDay(day)
                    cell?.configure(selectedDays: self.viewModel.repeatDays)
                }
            }
            return cell
        case .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: NameCell.reuseID, for: indexPath)
            if let cell = cell as? NameCell {
                cell.configure(name: viewModel.name)
                cell.onNameChanged = { [weak self] text in self?.viewModel.name = text }
            }
            return cell
        case .sound:
            let cell = tableView.dequeueReusableCell(withIdentifier: SoundCell.reuseID, for: indexPath)
            if let cell = cell as? SoundCell {
                let soundName = viewModel.availableSounds
                    .first(where: { $0.id == viewModel.soundID })?.name ?? "По умолчанию"
                cell.configure(soundName: soundName)
                cell.onPreviewTapped = { [weak self] in
                    guard let self else { return }
                    self.viewModel.previewSound(self.viewModel.soundID)
                }
            }
            return cell
        case .volume:
            let cell = tableView.dequeueReusableCell(withIdentifier: VolumeCell.reuseID, for: indexPath)
            if let cell = cell as? VolumeCell {
                cell.configure(volume: viewModel.volume, fadeIn: viewModel.volumeFadeIn)
            }
            return cell
        case .vibration:
            let cell = tableView.dequeueReusableCell(withIdentifier: VibrationCell.reuseID, for: indexPath)
            if let cell = cell as? VibrationCell {
                cell.configure(isOn: viewModel.vibrationEnabled)
                cell.onToggled = { [weak self] isOn in self?.viewModel.vibrationEnabled = isOn }
            }
            return cell
        case .penalty:
            let cell = tableView.dequeueReusableCell(withIdentifier: PenaltyCell.reuseID, for: indexPath)
            if let cell = cell as? PenaltyCell {
                cell.configure(amount: viewModel.penaltyAmount)
                cell.onValueChanged = { [weak self] amount in self?.setPenaltyAmount(amount) }
            }
            return cell
        case .progressiveScale where indexPath.row == 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: ProgressiveScaleCell.reuseID, for: indexPath)
            if let cell = cell as? ProgressiveScaleCell {
                cell.configure(isOn: viewModel.progressiveScale)
                cell.onToggled = { [weak self] isOn in self?.setProgressiveScale(isOn) }
            }
            return cell
        case .progressiveScale:
            let cell = tableView.dequeueReusableCell(withIdentifier: ProgressivePreviewCell.reuseID, for: indexPath)
            if let cell = cell as? ProgressivePreviewCell {
                cell.configure(text: viewModel.progressiveScalePreview)
            }
            return cell
        case .snoozeTime:
            let cell = tableView.dequeueReusableCell(withIdentifier: SnoozeSliderCell.reuseID, for: indexPath)
            if let cell = cell as? SnoozeSliderCell {
                cell.configure(minutes: viewModel.snoozeMinutes)
                cell.onValueChanged = { [weak self] minutes in self?.viewModel.snoozeMinutes = minutes }
            }
            return cell
        case .theme:
            let cell = tableView.dequeueReusableCell(withIdentifier: ThemeRowCell.reuseID, for: indexPath)
            if let cell = cell as? ThemeRowCell {
                cell.configure(themeName: viewModel.alarmThemeName)
            }
            return cell
        case .deleteAction:
            return tableView.dequeueReusableCell(withIdentifier: DeleteActionCell.reuseID, for: indexPath)
        }
    }
}

// MARK: - UITableViewDelegate

extension CreateAlarmViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 44 }
        switch section {
        case .timePicker: return 200
        case .repeatDays: return 60
        case .penalty: return 60
        default: return UITableView.automaticDimension
        }
    }

    /// Apply the shared card-style background so each `.insetGrouped` section
    /// (time picker, repeat days, name, sound, vibration, penalty, …) lifts off
    /// the page in light mode the same way the alarm-row cards do on the home
    /// screen.
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let totalRows = self.tableView(tableView, numberOfRowsInSection: indexPath.section)
        let position = CardRowPosition.resolve(row: indexPath.row, totalRows: totalRows)
        cell.styleAsCardRow(position: position)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .sound:
            showSoundPicker()
        case .volume:
            showVolumePicker()
        case .theme:
            // The full theme picker (`AlarmThemePickerViewController`) is
            // tracked by #151. Until it lands the row is a no-op so the form
            // doesn't push an empty placeholder VC. The chevron + value
            // chrome still surfaces the row's intent.
            break
        case .deleteAction:
            confirmDelete()
        default:
            return
        }
    }

    private func confirmDelete() {
        let alert = UIAlertController(
            title: "Удалить будильник?",
            message: "Это действие нельзя отменить.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            guard let self else { return }
            // ViewModel.delete forwards to AlarmRepository.delete, which itself
            // cancels the scheduled UNNotificationRequests via AlarmScheduler.
            // Returns false when the store is locked due to a corrupt blob
            // (issue #72) — surface the failure rather than dismiss the
            // sheet on a no-op delete.
            let didDelete = self.viewModel.delete()
            guard didDelete else {
                self.presentSaveError(
                    title: "Не удалось сохранить",
                    error: AlarmRepository.RepositoryError.persistBlocked
                )
                return
            }
            self.onDelete?()
            self.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        // Without a sourceView the action sheet crashes on iPad popovers.
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    private func showSoundPicker() {
        let picker = SoundPickerViewController(
            sounds: viewModel.availableSounds,
            selectedID: viewModel.soundID,
            onSelect: { [weak self] soundID in
                self?.viewModel.soundID = soundID
            },
            previewSound: { [weak self] soundID in
                self?.viewModel.previewSound(soundID)
            }
        )
        navigationController?.pushViewController(picker, animated: true)
    }

    /// Push the new `VolumePickerViewController` (#150). The picker reports
    /// every slider / switch change live so dismissing on the back chevron
    /// is "auto-save" — the parent's `viewWillAppear` then refreshes the
    /// volume row to render the new value.
    private func showVolumePicker() {
        let picker = VolumePickerViewController(
            volume: viewModel.volume,
            fadeIn: viewModel.volumeFadeIn
        ) { [weak self] volume, fadeIn in
            self?.viewModel.volume = volume
            self?.viewModel.volumeFadeIn = fadeIn
        }
        navigationController?.pushViewController(picker, animated: true)
    }
}

// MARK: - Section header

/// Custom section-header view rendered above each `.insetGrouped` group on
/// the create/edit form. Replaces the default footnote-cased header with the
/// design-system `caps` role + tracking so headers read at the same weight
/// as the rest of the brand-refreshed surfaces (#143, builds on #135).
private final class SectionHeaderView: UIView {

    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = .clear
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.lg),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sm)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
