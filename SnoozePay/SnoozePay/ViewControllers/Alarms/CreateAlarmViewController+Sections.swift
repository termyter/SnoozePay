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
        tableView.register(RepeatModeCell.self, forCellReuseIdentifier: RepeatModeCell.reuseID)
        tableView.register(NameCell.self, forCellReuseIdentifier: NameCell.reuseID)
        tableView.register(SoundCell.self, forCellReuseIdentifier: SoundCell.reuseID)
        tableView.register(VibrationCell.self, forCellReuseIdentifier: VibrationCell.reuseID)
        tableView.register(PenaltyCell.self, forCellReuseIdentifier: PenaltyCell.reuseID)
        tableView.register(ProgressiveScaleCell.self, forCellReuseIdentifier: ProgressiveScaleCell.reuseID)
        tableView.register(SnoozeSliderCell.self, forCellReuseIdentifier: SnoozeSliderCell.reuseID)
        tableView.register(ThemeRowCell.self, forCellReuseIdentifier: ThemeRowCell.reuseID)
    }

    /// Route a row of the merged Звук/Тема/Вибрация settings card (#231) to
    /// its dedicated builder.
    func makeSettingsCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        guard let row = SettingsRow(rawValue: indexPath.row) else { return UITableViewCell() }
        switch row {
        case .sound:     return makeSoundCell(tableView, at: indexPath)
        case .theme:     return makeThemeCell(tableView, at: indexPath)
        case .vibration: return makeVibrationCell(tableView, at: indexPath)
        }
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
                // Emptying the day set under «Еженедельно» makes the form
                // unsavable — say so under the pill right away (#633).
                self.refreshRepeatValidity()
            }
        }
        return cell
    }

    /// Никогда / Еженедельно pill + behaviour hint under the day chips
    /// (#229). The closure repaints the cell first and only then asks the
    /// table to re-measure — the never/weekly hints wrap to different line
    /// counts, so measuring against the stale hint would clip the new one.
    func makeRepeatModeCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RepeatModeCell.reuseID, for: indexPath)
        if let cell = cell as? RepeatModeCell {
            cell.configure(mode: viewModel.repeatMode, hint: viewModel.repeatModeHint)
            cell.onModeChanged = { [weak self] mode in
                guard let self else { return }
                self.viewModel.repeatMode = mode
                // Repaints the pill + hint and dims «Готово» when the new mode
                // is «Еженедельно» without days (#633); the height change is
                // animated there without reloading the cell, since a reload
                // would tear down the pill mid-gesture.
                self.refreshRepeatValidity()
            }
        }
        return cell
    }

    // MARK: - Repeat-mode validation (#633)

    /// Re-evaluate whether the form describes a schedule the app can build,
    /// after a day chip or the repeat pill changed. Repaints the hint under
    /// the pill and dims «Готово» while «Еженедельно» has no days — the
    /// combination that used to be saved as a one-shot alarm in silence.
    ///
    /// Lives next to the two rows that can produce that state; also called
    /// from `viewDidLoad` so the button starts in the right state.
    func refreshRepeatValidity() {
        saveButton?.isEnabled = viewModel.canSave
        guard let cell = tableView.cellForRow(at: repeatModeIndexPath) as? RepeatModeCell else { return }
        cell.configure(mode: viewModel.repeatMode, hint: viewModel.repeatModeHint)
        guard view.window != nil else { return }
        // The hints wrap to different line counts; re-measure without a reload
        // so the pill isn't torn down mid-gesture.
        tableView.performBatchUpdates(nil)
    }

    /// Scrolls the reason for a refused save into view. The hint under the
    /// pill already carries it, so there is nothing to add — only to show.
    func revealRepeatModeRow() {
        refreshRepeatValidity()
        tableView.scrollToRow(at: repeatModeIndexPath, at: .middle, animated: true)
    }

    private var repeatModeIndexPath: IndexPath {
        IndexPath(row: RepeatRow.mode.rawValue, section: Section.repeatDays.rawValue)
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
                .first(where: { $0.id == viewModel.soundID })?.name
                ?? Localized.text("create_alarm.sound.fallback")
            cell.configure(soundName: soundName)
            cell.onPreviewTapped = { [weak self] in
                guard let self else { return }
                self.viewModel.previewSound(self.viewModel.soundID)
            }
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
            cell.configure(
                isOn: viewModel.progressiveScale,
                chain: viewModel.progressiveChain,
                accessibilityChain: viewModel.progressiveScalePreview
            )
            cell.onToggled = { [weak self] isOn in self?.setProgressiveScale(isOn) }
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
            // V2 thumbnail variant: pass the live theme so the leading 28pt
            // tile renders the matching gradient/photo (#163).
            cell.configure(theme: viewModel.theme, themeName: viewModel.alarmThemeName)
        }
        return cell
    }
}
