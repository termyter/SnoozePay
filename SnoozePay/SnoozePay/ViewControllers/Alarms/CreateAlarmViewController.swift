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

    /// Section order matches the V2 AlarmEdit artboard (`SPMore2.jsx` /
    /// #231): name first (auto-focus on create), then time picker, repeat
    /// days, snooze slider, the merged Звук/Тема/Вибрация settings card,
    /// the snooze-price card and finally the progressive-mode card. The
    /// destructive delete action lives in a fixed footer below the table
    /// (edit-mode only), not in a table section.
    enum Section: Int, CaseIterable {
        case name = 0
        case timePicker
        case repeatDays
        case snoozeTime
        /// Single card with exactly three rows: Звук / Тема / Вибрация.
        case settings
        case penalty
        case progressiveScale
    }

    /// Rows inside the merged `Section.settings` card (#231).
    enum SettingsRow: Int, CaseIterable {
        case sound = 0
        case theme
        case vibration
    }

    /// Rows inside `Section.repeatDays` (#229): the Пн-Вс day chips and the
    /// Никогда / Еженедельно repeat-mode pill below them.
    enum RepeatRow: Int, CaseIterable {
        case days = 0
        case mode
    }

    /// Convenience accessor used by `+Pickers.showThemePicker` so that file
    /// does not have to depend on `Section`/`SettingsRow` raw values directly.
    var themeRowIndexPath: IndexPath {
        IndexPath(row: SettingsRow.theme.rawValue, section: Section.settings.rawValue)
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
        view.backgroundColor = AppColors.bg0
        setupNavigationBar()
        setupTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh the sound + theme rows in case the user picked a new value
        // on a pushed picker and is returning here.
        tableView.reloadSections(IndexSet([Section.settings.rawValue]), with: .none)
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
        // V2 nav bar — left X close chip, centered caps title, right `Готово`
        // SPButton(.money, .sm). The UIKit navigation bar still owns layout
        // (we keep `title` set on viewDidLoad for accessibility), but the
        // left/right items are custom views so the brand styling sticks.
        // Matches `SPScreensV2.jsx` lines 496-502.
        let closeButton = UIButton(type: .system)
        closeButton.setImage(
            UIImage(systemName: "xmark")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            ),
            for: .normal
        )
        closeButton.tintColor = AppColors.fg1
        closeButton.backgroundColor = AppColors.whiteOverlay06
        closeButton.layer.cornerRadius = 18
        closeButton.layer.masksToBounds = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        closeButton.accessibilityLabel = "Закрыть"
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: closeButton)

        let saveButton = SPButton(
            title: "Готово",
            variant: .money,
            size: .sm
        )
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: saveButton)

        // V2 title sits in caps + tracking. UIKit nav titles don't support
        // attributed text directly via `navigationItem.title`, so install a
        // custom title view label.
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(
            string: (viewModel.isEditing ? "Редактировать" : "Новый будильник").uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        titleLabel.textAlignment = .center
        navigationItem.titleView = titleLabel
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
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        guard viewModel.isEditing else {
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            return
        }

        // Edit mode: destructive "Удалить будильник" CTA lives in a fixed
        // footer below the scrolling form — `padding: 0 16px 24px` per the
        // V2 AlarmEdit artboard (`SPMore2.jsx`, #231). The table's bottom is
        // pinned to the footer's top so content never hides behind the CTA.
        let footer = UIView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.backgroundColor = AppColors.bg0
        view.addSubview(footer)

        let deleteButton = SPButton(
            title: "Удалить будильник",
            variant: .pain,
            size: .lg,
            fullWidth: true
        )
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        footer.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            deleteButton.topAnchor.constraint(equalTo: footer.topAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: AppSpacing.sp4),
            deleteButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -AppSpacing.sp4),
            deleteButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp2
            )
        ])
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func deleteTapped() {
        confirmDelete()
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
    /// toggle callback (#182). The cell owns its own chain-row visibility +
    /// pain-tint flip (#231); the controller only persists the new value and
    /// asks the table to re-measure the now taller/shorter card.
    func setProgressiveScale(_ isOn: Bool) {
        viewModel.progressiveScale = isOn
        guard view.window != nil else { return }
        // Animate the self-sizing height change without reloading the cell —
        // a reload would tear down the SPSwitch mid-gesture.
        tableView.performBatchUpdates(nil)
    }

    /// `internal` so `+Sections.makePenaltyCell` can wire the slider callback
    /// (#182).
    func setPenaltyAmount(_ amount: Double) {
        viewModel.penaltyAmount = amount
        // Refresh the progressive card's 50 → 100 → 200 → 400 ₽ chain so it
        // tracks the new base price live.
        let progressiveIndexPath = IndexPath(row: 0, section: Section.progressiveScale.rawValue)
        if let cell = tableView.cellForRow(at: progressiveIndexPath) as? ProgressiveScaleCell {
            cell.configure(
                isOn: viewModel.progressiveScale,
                chain: viewModel.progressiveChain,
                accessibilityChain: viewModel.progressiveScalePreview
            )
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
        case .settings:
            return SettingsRow.allCases.count
        case .repeatDays:
            return RepeatRow.allCases.count
        default:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .penalty: return "ШТРАФ ЗА ОТКЛАДЫВАНИЕ"
        case .snoozeTime: return "ВРЕМЯ ОТКЛАДЫВАНИЯ"
        // Name no longer carries a header — the large in-cell placeholder
        // already reads as the field's purpose (#143). The settings and
        // progressive cards are header-less per the V2 artboard (#231).
        // The repeat card's `ПОВТОР` caption moved inside `RepeatModeCell`
        // so it sits between the day chips and the mode pill, matching the
        // V2 RepeatSegmented layout (#229).
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

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch section {
        case .timePicker:        return makeTimePickerCell(tableView, at: indexPath)
        case .repeatDays:
            return RepeatRow(rawValue: indexPath.row) == .mode
                ? makeRepeatModeCell(tableView, at: indexPath)
                : makeRepeatDaysCell(tableView, at: indexPath)
        case .name:              return makeNameCell(tableView, at: indexPath)
        case .settings:          return makeSettingsCell(tableView, at: indexPath)
        case .penalty:           return makePenaltyCell(tableView, at: indexPath)
        case .progressiveScale:  return makeProgressiveScaleToggleCell(tableView, at: indexPath)
        case .snoozeTime:        return makeSnoozeTimeCell(tableView, at: indexPath)
        }
    }
}

// MARK: - UITableViewDelegate

extension CreateAlarmViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 44 }
        switch section {
        case .timePicker: return 200
        // Day-chips row keeps its fixed 60pt; the repeat-mode pill + hint
        // below self-sizes (the hint wraps to 1–2 lines per mode, #229).
        case .repeatDays:
            return RepeatRow(rawValue: indexPath.row) == .days ? 60 : UITableView.automaticDimension
        // V2 penalty row stacks a moneyMd value label above a 40pt chip row
        // — the prior 60pt height clipped the chip ladder, so bump to 96pt.
        case .penalty: return 96
        default: return UITableView.automaticDimension
        }
    }

    /// Apply the shared card-style background so each `.insetGrouped` section
    /// (time picker, repeat days, name, settings, penalty, …) lifts off the
    /// page in light mode the same way the alarm-row cards do on the home
    /// screen. The progressive card owns its background (pain-tinted gradient
    /// when armed, #231) so the generic recipe must not stomp it.
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if cell is ProgressiveScaleCell { return }
        let totalRows = self.tableView(tableView, numberOfRowsInSection: indexPath.section)
        let position = CardRowPosition.resolve(row: indexPath.row, totalRows: totalRows)
        cell.styleAsCardRow(position: position)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        guard section == .settings, let row = SettingsRow(rawValue: indexPath.row) else { return }
        switch row {
        case .sound:
            showSoundPicker()
        case .theme:
            showThemePicker()
        case .vibration:
            return
        }
    }

}

// `SectionHeaderView` lives in `Views/DesignSystem/SectionHeaderView.swift` so
// the same caps-styled header can be reused by Settings + Transaction history
// without copy-paste (#182).
