import UIKit

// MARK: - Section cell builders
//
// Extracted from `CreateAlarmViewController.swift` (#182) so the host file
// stays under SwiftLint's `file_length` cap. Each helper owns its row's
// dequeue + configure + callback wiring; behaviour is verbatim — only the
// physical location moved.

extension CreateAlarmViewController {

    /// Register every per-row cell type so `dequeueReusableCell(...)` calls in
    /// the helpers below always succeed. Called once from `setupTableView`.
    func registerSectionCells(in tableView: UITableView) {
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
    }

    func makeTimePickerCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TimePickerCell.reuseID, for: indexPath)
        if let cell = cell as? TimePickerCell {
            cell.configure(time: viewModel.time)
            cell.onTimeChanged = { [weak self] date in self?.viewModel.time = date }
        }
        return cell
    }

    func makeRepeatDaysCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
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
    }

    func makeNameCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: NameCell.reuseID, for: indexPath)
        if let cell = cell as? NameCell {
            cell.configure(name: viewModel.name)
            cell.onNameChanged = { [weak self] text in self?.viewModel.name = text }
        }
        return cell
    }

    func makeSoundCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
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
    }

    func makeVolumeCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VolumeCell.reuseID, for: indexPath)
        if let cell = cell as? VolumeCell {
            cell.configure(volume: viewModel.volume, fadeIn: viewModel.volumeFadeIn)
        }
        return cell
    }

    func makeVibrationCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VibrationCell.reuseID, for: indexPath)
        if let cell = cell as? VibrationCell {
            cell.configure(isOn: viewModel.vibrationEnabled)
            cell.onToggled = { [weak self] isOn in self?.viewModel.vibrationEnabled = isOn }
        }
        return cell
    }

    func makePenaltyCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PenaltyCell.reuseID, for: indexPath)
        if let cell = cell as? PenaltyCell {
            cell.configure(amount: viewModel.penaltyAmount)
            cell.onValueChanged = { [weak self] amount in self?.setPenaltyAmount(amount) }
        }
        return cell
    }

    func makeProgressiveScaleToggleCell(
        _ tableView: UITableView,
        at indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ProgressiveScaleCell.reuseID, for: indexPath)
        if let cell = cell as? ProgressiveScaleCell {
            cell.configure(isOn: viewModel.progressiveScale)
            cell.onToggled = { [weak self] isOn in self?.setProgressiveScale(isOn) }
        }
        return cell
    }

    func makeProgressivePreviewCell(
        _ tableView: UITableView,
        at indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ProgressivePreviewCell.reuseID, for: indexPath)
        if let cell = cell as? ProgressivePreviewCell {
            cell.configure(text: viewModel.progressiveScalePreview)
        }
        return cell
    }

    func makeSnoozeTimeCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SnoozeSliderCell.reuseID, for: indexPath)
        if let cell = cell as? SnoozeSliderCell {
            cell.configure(minutes: viewModel.snoozeMinutes)
            cell.onValueChanged = { [weak self] minutes in self?.viewModel.snoozeMinutes = minutes }
        }
        return cell
    }

    func makeThemeCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ThemeRowCell.reuseID, for: indexPath)
        if let cell = cell as? ThemeRowCell {
            cell.configure(themeName: viewModel.alarmThemeName)
        }
        return cell
    }

    func makeDeleteActionCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: DeleteActionCell.reuseID, for: indexPath)
    }
}
