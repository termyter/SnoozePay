import UIKit

// MARK: - Picker push handlers + delete confirmation
//
// Extracted from `CreateAlarmViewController.swift` (#182) to keep the host
// file under SwiftLint's `file_length` cap. Behaviour is unchanged —
// these used to be `private func`s on the main type.

extension CreateAlarmViewController {

    /// V2 bottom-sheet confirmation before destroying the alarm being edited
    /// (#163). Replaces the pre-refresh `UIAlertController.actionSheet` flow
    /// with the brand-aligned `ConfirmDeleteAlarmViewController` so the
    /// destructive copy reads in the same caps/h2/pain typography ramp as the
    /// rest of the V2 surfaces. The actual `viewModel.delete()` + onDelete
    /// + dismiss chain is unchanged — only the surface that asks "are you
    /// sure?" moved.
    func confirmDelete() {
        let sheet = ConfirmDeleteAlarmViewController { [weak self] in
            guard let self else { return }
            // ViewModel.delete forwards to AlarmRepository.delete, which
            // cancels the scheduled UNNotificationRequests via AlarmScheduler.
            // Returns false when the store is locked due to a corrupt blob
            // (issue #72) — surface the failure rather than dismiss the
            // create-alarm form on a no-op delete.
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
        }
        present(sheet, animated: true)
    }

    func showThemePicker() {
        let picker = AlarmThemePickerViewController(
            currentTheme: viewModel.theme,
            onSelect: { [weak self] theme in
                guard let self else { return }
                self.viewModel.theme = theme
                // Update the trailing-value label inline so the user sees
                // the new theme name without waiting for `viewWillAppear`'s
                // section reload (which doesn't fire for the in-place update
                // that follows the imperative pop).
                let indexPath = IndexPath(row: 0, section: themeSectionIndex)
                if let cell = self.tableView.cellForRow(at: indexPath) as? ThemeRowCell {
                    cell.configure(theme: self.viewModel.theme, themeName: self.viewModel.alarmThemeName)
                }
            }
        )
        navigationController?.pushViewController(picker, animated: true)
    }

    func showSoundPicker() {
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
    func showVolumePicker() {
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
