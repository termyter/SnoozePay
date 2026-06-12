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
    ///
    /// Body copy is composed per the `SPMore2.jsx` artboard (#277): the
    /// alarm's identity line («Будни · Пн–Пт · 07:00») followed by the
    /// balance-stays-put reassurance with the live balance interpolated.
    func confirmDelete() {
        let body = AlarmDeletionCopy.body(
            contextLine: AlarmDeletionCopy.contextLine(
                repeatDays: viewModel.repeatDays,
                repeatMode: viewModel.repeatMode,
                time: viewModel.time
            ),
            balance: BalanceService.shared.balance
        )
        let sheet = ConfirmDeleteAlarmViewController(body: body) { [weak self] in
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
                if let cell = self.tableView.cellForRow(at: self.themeRowIndexPath) as? ThemeRowCell {
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
}
