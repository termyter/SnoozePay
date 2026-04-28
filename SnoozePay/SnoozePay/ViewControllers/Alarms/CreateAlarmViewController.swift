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

    /// `internal` so the cross-file `+Sections` extension can read VM state
    /// inside the row factory helpers (#182).
    let viewModel: CreateAlarmViewModel

    // MARK: - UI

    /// `internal` so the cross-file `+Pickers` extension can mutate the
    /// theme row in place after the picker pops (#182).
    let tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .insetGrouped)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Sections

    /// Section order matches the #143 PM spec: name first (auto-focus on
    /// create), then time picker, repeat days, snooze slider, penalty,
    /// progressive scale, sound, vibration, theme, and finally the
    /// destructive delete action (edit-mode only).
    /// `internal` so the cross-file `+Pickers` extension can resolve
    /// `Section.theme.rawValue` for the imperative cell refresh after the
    /// picker pops (#182).
    enum Section: Int, CaseIterable {
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

    /// Convenience accessor used by `+Pickers.showThemePicker` so that file
    /// does not have to depend on `Section.rawValue` directly.
    var themeSectionIndex: Int { Section.theme.rawValue }

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
        view.backgroundColor = AppColors.bg0
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
        registerSectionCells(in: tableView)

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
    /// `LocalizedError` (issues #72, #118). `internal` so the `+Pickers`
    /// extension can surface a delete failure (#182).
    func presentSaveError(title: String, error: LocalizedError) {
        let alert = UIAlertController(
            title: title,
            message: error.errorDescription ?? "Попробуйте ещё раз.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - View-model bridges

    /// `internal` so `+Sections.makeProgressiveScaleToggleCell` can wire the
    /// toggle callback (#182).
    func setProgressiveScale(_ isOn: Bool) {
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

    /// `internal` so `+Sections.makePenaltyCell` can wire the slider callback
    /// (#182).
    func setPenaltyAmount(_ amount: Double) {
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

    // swiftlint:disable:next cyclomatic_complexity
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch section {
        case .timePicker:        return makeTimePickerCell(tableView, at: indexPath)
        case .repeatDays:        return makeRepeatDaysCell(tableView, at: indexPath)
        case .name:              return makeNameCell(tableView, at: indexPath)
        case .sound:             return makeSoundCell(tableView, at: indexPath)
        case .volume:            return makeVolumeCell(tableView, at: indexPath)
        case .vibration:         return makeVibrationCell(tableView, at: indexPath)
        case .penalty:           return makePenaltyCell(tableView, at: indexPath)
        case .progressiveScale where indexPath.row == 0:
            return makeProgressiveScaleToggleCell(tableView, at: indexPath)
        case .progressiveScale:  return makeProgressivePreviewCell(tableView, at: indexPath)
        case .snoozeTime:        return makeSnoozeTimeCell(tableView, at: indexPath)
        case .theme:             return makeThemeCell(tableView, at: indexPath)
        case .deleteAction:      return makeDeleteActionCell(tableView, at: indexPath)
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
            showThemePicker()
        case .deleteAction:
            confirmDelete()
        default:
            return
        }
    }

}

// `SectionHeaderView` lives in `Views/DesignSystem/SectionHeaderView.swift` so
// the same caps-styled header can be reused by Settings + Transaction history
// without copy-paste (#182).
