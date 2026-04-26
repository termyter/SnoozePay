import UIKit
import AudioToolbox

/// Screen for creating or editing an alarm.
/// Uses a static table view with sections for each setting group.
class CreateAlarmViewController: UIViewController {

    // MARK: - Properties

    var onSave: (() -> Void)?
    /// Invoked after the user confirms deletion of the alarm being edited so the
    /// presenter can refresh its list. Defaults to nil for new alarms (delete row
    /// is hidden in create mode).
    var onDelete: (() -> Void)?
    private let viewModel: CreateAlarmViewModel

    // MARK: - UI

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    // Time picker
    private let timePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()

    // Day buttons
    private var dayButtons: [UIButton] = []
    private let dayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    // Penalty slider
    private let penaltySlider: UISlider = {
        let s = UISlider()
        s.minimumValue = 10
        s.maximumValue = 1000
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let penaltyValueLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 17)
        l.textColor = AppColors.accentOrange
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // Progressive scale toggle
    private let progressiveToggle: UISwitch = {
        let sw = UISwitch()
        sw.onTintColor = AppColors.accentOrange
        return sw
    }()

    private let progressivePreviewLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = AppColors.accentOrange
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // Snooze stepper. The "X мин" value is shown in the cell's
    // `detailTextLabel` (UITableViewCell `.value1` style), not via a custom
    // stack accessory — `UIStackView.sizeToFit()` did not produce a sensible
    // intrinsic size for a stepper + label combo, leaving the stepper drawn
    // at the cell's top-left and clipping the value label.
    private let snoozeStepper: UIStepper = {
        let s = UIStepper()
        s.minimumValue = 1
        s.maximumValue = 30
        s.stepValue = 1
        return s
    }()

    // Vibration toggle
    private let vibrationToggle: UISwitch = {
        let sw = UISwitch()
        sw.onTintColor = AppColors.accentGreen
        return sw
    }()

    // Name field
    private let nameField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Название"
        tf.font = UIFont.systemFont(ofSize: 17)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
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
        /// In create mode `numberOfRowsInSection` returns 0, hiding the section
        /// entirely (including its background pill).
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
        // Targets must be wired exactly once on these shared controls.
        // Wiring them in `cellForRowAt` accumulated duplicate handlers on every
        // reload, multiplying penalty/snooze updates per single user action.
        wireControlTargets()
        populateFromViewModel()
    }

    private func wireControlTargets() {
        penaltySlider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        progressiveToggle.addTarget(self, action: #selector(progressiveToggled(_:)), for: .valueChanged)
        snoozeStepper.addTarget(self, action: #selector(stepperChanged(_:)), for: .valueChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh sound row when returning from SoundPickerViewController
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        // Pin to safe area on top so the first section's "ПОВТОР" header is
        // not clipped under the navigation bar. Bottom can stay at view edge
        // since insetGrouped style handles bottom safe area via contentInset.
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func populateFromViewModel() {
        timePicker.date = viewModel.time
        penaltySlider.value = Float(viewModel.penaltyAmount)
        penaltyValueLabel.text = "\(Int(viewModel.penaltyAmount)) ₽"
        progressiveToggle.isOn = viewModel.progressiveScale
        progressivePreviewLabel.text = viewModel.progressiveScalePreview
        progressivePreviewLabel.isHidden = !viewModel.progressiveScale
        snoozeStepper.value = Double(viewModel.snoozeMinutes)
        vibrationToggle.isOn = viewModel.vibrationEnabled
        nameField.text = viewModel.name
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        // Collect values from controls back into viewModel
        viewModel.time = timePicker.date
        viewModel.name = nameField.text ?? "Будильник"
        viewModel.penaltyAmount = Double(penaltySlider.value)
        viewModel.progressiveScale = progressiveToggle.isOn
        viewModel.snoozeMinutes = Int(snoozeStepper.value)
        viewModel.vibrationEnabled = vibrationToggle.isOn

        viewModel.save()
        onSave?()
        dismiss(animated: true)
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        // Round to nearest 10
        let rounded = (sender.value / 10).rounded() * 10
        sender.value = rounded
        viewModel.penaltyAmount = Double(rounded)
        penaltyValueLabel.text = "\(Int(rounded)) ₽"
        progressivePreviewLabel.text = viewModel.progressiveScalePreview
    }

    @objc private func progressiveToggled(_ sender: UISwitch) {
        viewModel.progressiveScale = sender.isOn
        progressivePreviewLabel.text = viewModel.progressiveScalePreview
        progressivePreviewLabel.isHidden = !sender.isOn

        // Detach the shared preview label from its previous host cell before the
        // table view rebuilds the section. Reusing the same view across cells
        // without removing it first leaves stale auto-layout constraints attached
        // to a discarded cell, which crashes UIKit when it tries to lay out a
        // table view that is not yet (or no longer) in the view hierarchy.
        progressivePreviewLabel.removeFromSuperview()

        // Skip animated updates if the view is detached from a window — UIKit
        // logs "told to layout its visible cells without being in the view
        // hierarchy" and may crash when applying the diff.
        guard view.window != nil else {
            tableView.reloadData()
            return
        }

        // Insert/delete the preview row instead of reloading the whole section.
        // This avoids tearing down the toggle row (which owns `progressiveToggle`
        // as accessoryView) on every flip and keeps the animation smooth.
        let previewIndexPath = IndexPath(row: 1, section: Section.progressiveScale.rawValue)
        tableView.performBatchUpdates({
            if sender.isOn {
                tableView.insertRows(at: [previewIndexPath], with: .fade)
            } else {
                tableView.deleteRows(at: [previewIndexPath], with: .fade)
            }
        })
    }

    @objc private func stepperChanged(_ sender: UIStepper) {
        viewModel.snoozeMinutes = Int(sender.value)
        // Update the visible cell's detail label in place. Avoids
        // `reloadRows`, which would recreate the cell mid-interaction and
        // drop the stepper's gesture state.
        let snoozePath = IndexPath(row: 0, section: Section.snoozeTime.rawValue)
        if let cell = tableView.cellForRow(at: snoozePath) {
            cell.detailTextLabel?.text = snoozeMinutesText
        }
    }

    private var snoozeMinutesText: String {
        "\(viewModel.snoozeMinutes) мин"
    }

    @objc private func previewSoundTapped() {
        viewModel.previewSound(viewModel.soundID)
    }

    @objc private func dayButtonTapped(_ sender: UIButton) {
        let day = sender.tag
        viewModel.toggleDay(day)
        // Light haptic confirms the toggle without being intrusive — matches the
        // tactile feel of native iOS segmented controls.
        UISelectionFeedbackGenerator().selectionChanged()
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: { [weak self] in
                self?.applyDayButtonStyle(sender, isSelected: self?.viewModel.repeatDays.contains(day) ?? false)
            }
        )
        // Other buttons (none should change state, but keeps the visual model
        // single-source-of-truth in case toggleDay ever mutates more than one).
        updateDayButtons(except: sender)
    }

    private func updateDayButtons(except skip: UIButton? = nil) {
        for (index, button) in dayButtons.enumerated() where button !== skip {
            let isSelected = viewModel.repeatDays.contains(index)
            applyDayButtonStyle(button, isSelected: isSelected)
        }
    }

    /// Visual treatment for a single weekday pill. Selected — filled accent with
    /// white text. Unselected — clear fill with a hairline border that adapts to
    /// dark mode via `UIColor.separator`. Centralised so toggle-tap animation and
    /// initial render stay in sync.
    private func applyDayButtonStyle(_ button: UIButton, isSelected: Bool) {
        if isSelected {
            button.backgroundColor = AppColors.accentBlue
            button.setTitleColor(.white, for: .normal)
            button.layer.borderWidth = 0
            button.layer.borderColor = UIColor.clear.cgColor
        } else {
            button.backgroundColor = .clear
            button.setTitleColor(AppColors.textSecondary, for: .normal)
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.separator.cgColor
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
            // Hide the destructive row entirely when creating a new alarm —
            // there's nothing to delete yet.
            return viewModel.isEditing ? 1 : 0
        default:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .timePicker: return nil
        case .repeatDays: return "ПОВТОР"
        case .name: return "НАЗВАНИЕ"
        case .sound: return "ЗВУК"
        case .vibration: return nil
        case .penalty: return "ШТРАФ ЗА ОТКЛАДЫВАНИЕ"
        case .progressiveScale: return nil
        case .snoozeTime: return "ВРЕМЯ ОТКЛАДЫВАНИЯ"
        case .deleteAction: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        // `.value1` is used only for the snooze row so its detail label
        // ("X мин") sits between the title and the stepper accessory.
        // All other rows use `.default` because they either own custom
        // content or use accessoryView/accessoryType only.
        let style: UITableViewCell.CellStyle = (section == .snoozeTime) ? .value1 : .default
        let cell = UITableViewCell(style: style, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.backgroundColor = .secondarySystemBackground

        switch section {
        case .timePicker:
            cell.contentView.addSubview(timePicker)
            NSLayoutConstraint.activate([
                timePicker.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                timePicker.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                timePicker.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                timePicker.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
            ])

        case .repeatDays:
            let container = makeDayPicker()
            container.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(container)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: AppSpacing.lg),
                container.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -AppSpacing.lg),
                container.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: AppSpacing.sm),
                container.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -AppSpacing.sm),
                container.heightAnchor.constraint(equalToConstant: 44)
            ])

        case .name:
            cell.contentView.addSubview(nameField)
            NSLayoutConstraint.activate([
                nameField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: AppSpacing.lg),
                nameField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -AppSpacing.lg),
                nameField.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                nameField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                nameField.heightAnchor.constraint(equalToConstant: 48)
            ])

        case .sound:
            cell.textLabel?.text = "Звук"
            cell.accessoryView = makeSoundAccessoryView()
            cell.selectionStyle = .default

        case .vibration:
            cell.textLabel?.text = "Вибрация"
            cell.accessoryView = vibrationToggle

        case .penalty:
            let stack = UIStackView(arrangedSubviews: [penaltySlider, penaltyValueLabel])
            stack.axis = .horizontal
            stack.spacing = AppSpacing.md
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: AppSpacing.lg),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -AppSpacing.lg),
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: AppSpacing.md),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -AppSpacing.md)
            ])

        case .progressiveScale:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Прогрессивная шкала"
                cell.accessoryView = progressiveToggle
            } else {
                // Preview row. The label is a stored property reused across cells,
                // so detach it from any previous host before re-attaching. Stale
                // constraints on a discarded cell crash UIKit during layout.
                // Text is kept fresh by `progressiveToggled` and `sliderChanged`.
                progressivePreviewLabel.removeFromSuperview()
                cell.contentView.addSubview(progressivePreviewLabel)
                NSLayoutConstraint.activate([
                    progressivePreviewLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: AppSpacing.lg),
                    progressivePreviewLabel.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -AppSpacing.lg),
                    progressivePreviewLabel.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: AppSpacing.sm),
                    progressivePreviewLabel.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -AppSpacing.sm)
                ])
            }

        case .snoozeTime:
            cell.textLabel?.text = "Откладывать на"
            cell.detailTextLabel?.text = snoozeMinutesText
            cell.detailTextLabel?.textColor = .label
            cell.accessoryView = snoozeStepper

        case .deleteAction:
            // Centered red text mimics iOS Settings' destructive row pattern
            // (see Calendar.app "Delete Event"). selectionStyle=.default to give
            // the user tactile feedback before the confirmation alert appears.
            cell.textLabel?.text = "Удалить будильник"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = UIFont.systemFont(ofSize: 17, weight: .regular)
            cell.selectionStyle = .default
        }

        return cell
    }

    // MARK: - Day picker helper

    /// Builds the weekday picker row: 7 toggleable pills laid out edge-to-edge
    /// inside the cell. The cell itself already supplies the grouped-card
    /// background (insetGrouped table view + `secondarySystemBackground` cell
    /// background), so this stack only needs internal padding.
    private func makeDayPicker() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = AppSpacing.sm

        dayButtons = []
        for (index, name) in dayNames.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.tag = index
            button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            button.layer.cornerRadius = AppRadius.sm
            button.layer.masksToBounds = true
            button.addTarget(self, action: #selector(dayButtonTapped(_:)), for: .touchUpInside)

            applyDayButtonStyle(button, isSelected: viewModel.repeatDays.contains(index))

            dayButtons.append(button)
            stack.addArrangedSubview(button)
        }

        return stack
    }

    /// Builds the sound row's `accessoryView`: sound name label + play preview button + chevron.
    /// The chevron is required because setting `accessoryView` suppresses `accessoryType`,
    /// so without it the row offers no visual disclosure cue.
    private func makeSoundAccessoryView() -> UIStackView {
        let soundLabel = UILabel()
        let soundName = viewModel.availableSounds.first(where: { $0.id == viewModel.soundID })?.name
        soundLabel.text = soundName ?? "По умолчанию"
        soundLabel.textColor = .secondaryLabel
        soundLabel.font = UIFont.systemFont(ofSize: 17)
        soundLabel.sizeToFit()

        let playButton = UIButton(type: .system)
        let playImage = UIImage(systemName: "play.circle.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        )
        playButton.setImage(playImage, for: .normal)
        playButton.tintColor = AppColors.accentBlue
        playButton.addTarget(self, action: #selector(previewSoundTapped), for: .touchUpInside)
        playButton.sizeToFit()

        let chevronImage = UIImage(systemName: "chevron.right")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        let chevronImageView = UIImageView(image: chevronImage)
        chevronImageView.tintColor = .tertiaryLabel
        chevronImageView.sizeToFit()

        let stack = UIStackView(arrangedSubviews: [soundLabel, playButton, chevronImageView])
        stack.axis = .horizontal
        stack.spacing = AppSpacing.sm
        stack.alignment = .center
        stack.sizeToFit()
        let width = soundLabel.frame.width
            + playButton.frame.width
            + chevronImageView.frame.width
            + AppSpacing.sm * 2
            + 16
        let height = max(soundLabel.frame.height, playButton.frame.height, chevronImageView.frame.height)
        stack.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return stack
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .sound:
            // Sound picker navigation — simple action sheet for MVP
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
            self.viewModel.delete()
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
