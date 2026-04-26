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

    private enum Section: Int, CaseIterable {
        case timePicker = 0
        case repeatDays
        case name
        case sound
        case vibration
        case penalty
        case progressiveScale
        case snoozeTime
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
        // Refresh the sound row in case the user picked a new sound on
        // SoundPickerViewController and is returning here.
        tableView.reloadSections(IndexSet(integer: Section.sound.rawValue), with: .none)
    }

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
        tableView.register(VibrationCell.self, forCellReuseIdentifier: VibrationCell.reuseID)
        tableView.register(PenaltyCell.self, forCellReuseIdentifier: PenaltyCell.reuseID)
        tableView.register(ProgressiveScaleCell.self, forCellReuseIdentifier: ProgressiveScaleCell.reuseID)
        tableView.register(ProgressivePreviewCell.self, forCellReuseIdentifier: ProgressivePreviewCell.reuseID)
        tableView.register(SnoozeCell.self, forCellReuseIdentifier: SnoozeCell.reuseID)
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
        let didSave = viewModel.save()
        guard didSave else {
            // Persist failed (corrupt store / encode error). Surface the
            // failure inline so the user doesn't tap "Сохранить", see the
            // sheet dismiss, and assume their alarm landed (issue #72).
            presentRepositoryError(AlarmRepository.RepositoryError.persistBlocked)
            return
        }
        onSave?()
        dismiss(animated: true)
    }

    /// Inline alert for repository failures that block save/delete. Kept
    /// generic so the same call site can present any `LocalizedError`
    /// (issue #72).
    private func presentRepositoryError(_ error: LocalizedError) {
        let alert = UIAlertController(
            title: "Не удалось сохранить",
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
        case .name: return "НАЗВАНИЕ"
        case .sound: return "ЗВУК"
        case .penalty: return "ШТРАФ ЗА ОТКЛАДЫВАНИЕ"
        case .snoozeTime: return "ВРЕМЯ ОТКЛАДЫВАНИЯ"
        default: return nil
        }
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
            let cell = tableView.dequeueReusableCell(withIdentifier: SnoozeCell.reuseID, for: indexPath)
            if let cell = cell as? SnoozeCell {
                cell.configure(minutes: viewModel.snoozeMinutes)
                cell.onValueChanged = { [weak self] minutes in self?.viewModel.snoozeMinutes = minutes }
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
                self.presentRepositoryError(AlarmRepository.RepositoryError.persistBlocked)
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
}
