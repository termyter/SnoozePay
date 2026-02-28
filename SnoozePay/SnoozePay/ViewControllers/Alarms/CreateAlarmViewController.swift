import UIKit
import AudioToolbox

/// Screen for creating or editing an alarm.
/// Uses a static table view with sections for each setting group.
class CreateAlarmViewController: UIViewController {

    // MARK: - Properties

    var onSave: (() -> Void)?
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

    // Snooze stepper
    private let snoozeStepper: UIStepper = {
        let s = UIStepper()
        s.minimumValue = 1
        s.maximumValue = 30
        s.stepValue = 1
        return s
    }()

    private let snoozeValueLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 17)
        l.textColor = .label
        return l
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
        populateFromViewModel()
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
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
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
        snoozeValueLabel.text = "\(viewModel.snoozeMinutes) мин"
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
        progressivePreviewLabel.isHidden = !sender.isOn

        // Animate the preview row appearing/disappearing
        tableView.performBatchUpdates({
            tableView.reloadSections(
                IndexSet(integer: Section.progressiveScale.rawValue),
                with: .automatic
            )
        })
    }

    @objc private func stepperChanged(_ sender: UIStepper) {
        viewModel.snoozeMinutes = Int(sender.value)
        snoozeValueLabel.text = "\(viewModel.snoozeMinutes) мин"
    }

    @objc private func previewSoundTapped() {
        viewModel.previewSound(viewModel.soundID)
    }

    @objc private func dayButtonTapped(_ sender: UIButton) {
        let day = sender.tag
        viewModel.toggleDay(day)
        updateDayButtons()
    }

    private func updateDayButtons() {
        for (index, button) in dayButtons.enumerated() {
            let isSelected = viewModel.repeatDays.contains(index)
            button.backgroundColor = isSelected ? AppColors.accentBlue : .secondarySystemBackground
            button.setTitleColor(isSelected ? .white : .label, for: .normal)
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
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
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

            // Sound name label
            let soundLabel = UILabel()
            soundLabel.text = viewModel.availableSounds.first(where: { $0.id == viewModel.soundID })?.name ?? "По умолчанию"
            soundLabel.textColor = .secondaryLabel
            soundLabel.font = UIFont.systemFont(ofSize: 17)
            soundLabel.sizeToFit()

            // Play preview button
            let playButton = UIButton(type: .system)
            let playImage = UIImage(systemName: "play.circle.fill")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            )
            playButton.setImage(playImage, for: .normal)
            playButton.tintColor = AppColors.accentBlue
            playButton.addTarget(self, action: #selector(previewSoundTapped), for: .touchUpInside)
            playButton.sizeToFit()

            // Container stack for label + play button + disclosure
            let accessoryStack = UIStackView(arrangedSubviews: [soundLabel, playButton])
            accessoryStack.axis = .horizontal
            accessoryStack.spacing = AppSpacing.sm
            accessoryStack.alignment = .center
            accessoryStack.sizeToFit()
            accessoryStack.frame = CGRect(x: 0, y: 0,
                                          width: soundLabel.frame.width + playButton.frame.width + AppSpacing.sm + 16,
                                          height: max(soundLabel.frame.height, playButton.frame.height))
            cell.accessoryView = accessoryStack
            cell.selectionStyle = .default

        case .vibration:
            cell.textLabel?.text = "Вибрация"
            cell.accessoryView = vibrationToggle

        case .penalty:
            let stack = UIStackView(arrangedSubviews: [penaltySlider, penaltyValueLabel])
            stack.axis = .horizontal
            stack.spacing = AppSpacing.md
            stack.translatesAutoresizingMaskIntoConstraints = false
            penaltySlider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
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
                progressiveToggle.addTarget(self, action: #selector(progressiveToggled(_:)), for: .valueChanged)
                cell.accessoryView = progressiveToggle
            } else {
                // Preview row
                progressivePreviewLabel.text = viewModel.progressiveScalePreview
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
            snoozeValueLabel.text = "\(viewModel.snoozeMinutes) мин"
            snoozeValueLabel.sizeToFit()
            let stack = UIStackView(arrangedSubviews: [snoozeValueLabel, snoozeStepper])
            stack.axis = .horizontal
            stack.spacing = AppSpacing.sm
            stack.alignment = .center
            snoozeStepper.addTarget(self, action: #selector(stepperChanged(_:)), for: .valueChanged)
            stack.sizeToFit()
            cell.accessoryView = stack
        }

        return cell
    }

    // MARK: - Day picker helper

    private func makeDayPicker() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4

        dayButtons = []
        for (index, name) in dayNames.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.tag = index
            button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            button.layer.cornerRadius = 8
            button.layer.masksToBounds = true
            button.addTarget(self, action: #selector(dayButtonTapped(_:)), for: .touchUpInside)

            let isSelected = viewModel.repeatDays.contains(index)
            button.backgroundColor = isSelected ? AppColors.accentBlue : .tertiarySystemBackground
            button.setTitleColor(isSelected ? .white : .label, for: .normal)

            dayButtons.append(button)
            stack.addArrangedSubview(button)
        }

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
        guard let section = Section(rawValue: indexPath.section), section == .sound else { return }
        // Sound picker navigation — simple action sheet for MVP
        showSoundPicker()
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
