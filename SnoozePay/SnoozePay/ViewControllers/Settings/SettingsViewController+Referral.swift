import UIKit

// MARK: - Referral cells & actions
//
// Lifted out of `SettingsViewController.swift` so the parent file stays under
// the swiftlint file_length error threshold (issue #144). The stored-property
// surface (`friendCodeInput`, `referralService`, `ReferralRow`) lives on the
// main class because Swift forbids stored properties in extensions; everything
// else is a pure function over those properties and slots into this file.

extension SettingsViewController {

    /// Dispatches to one of three layouts (`myCode`, `friendInput`, `caption`).
    /// Centralising the switch keeps `cellForRowAt:` short and the row-index
    /// math next to the enum it indexes into.
    func makeReferralCell(at indexPath: IndexPath) -> UITableViewCell {
        guard let row = ReferralRow(rawValue: indexPath.row) else { return UITableViewCell() }
        switch row {
        case .myCode:      return makeMyCodeCell(at: indexPath)
        case .friendInput: return makeFriendInputCell(at: indexPath)
        case .caption:     return makeReferralCaptionCell(at: indexPath)
        }
    }

    /// Row 1 — "Ваш код" with the user's 6-char code and a copy icon.
    /// Tapping anywhere on the row copies the code (we forward the tap from
    /// `didSelectRowAt:` rather than wiring an inner tap-target so a bigger
    /// hit area falls out for free).
    func makeMyCodeCell(at indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ReferralMyCodeCell.reuseID,
            for: indexPath
        ) as? ReferralMyCodeCell else {
            assertionFailure("dequeueReusableCell returned wrong type for \(ReferralMyCodeCell.reuseID)")
            return UITableViewCell()
        }
        cell.configure(code: referralService.getMyCode())
        return cell
    }

    /// Row 2 — `SPInput` for the friend's code + small "Применить" SPButton.
    /// The cell owns the controls; we re-point `friendCodeInput` at its input
    /// on every dequeue so `handleApplyFriendCodeTapped` can surface inline
    /// validation messages on the instance currently on screen.
    func makeFriendInputCell(at indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ReferralFriendInputCell.reuseID,
            for: indexPath
        ) as? ReferralFriendInputCell else {
            assertionFailure("dequeueReusableCell returned wrong type for \(ReferralFriendInputCell.reuseID)")
            return UITableViewCell()
        }
        cell.configure(
            appliedCode: referralService.appliedFriendCode,
            delegate: self
        ) { [weak self] in
            self?.handleApplyFriendCodeTapped()
        }
        self.friendCodeInput = cell.input
        return cell
    }

    /// Row 3 — small grey caption line. Modeled as a real cell rather than a
    /// section footer so it inherits the card-row styling applied in
    /// `willDisplay`.
    func makeReferralCaptionCell(at indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ReferralCaptionCell.reuseID,
            for: indexPath
        ) as? ReferralCaptionCell else {
            assertionFailure("dequeueReusableCell returned wrong type for \(ReferralCaptionCell.reuseID)")
            return UITableViewCell()
        }
        cell.configure(text: "За каждого друга — +200 ₽ на ваш баланс")
        return cell
    }

    // MARK: - Actions

    /// Copies the user's referral code to the system pasteboard and shows a
    /// 1.5-second toast at the bottom-safe area. Chosen over a UIAlertController
    /// because a modal alert for "Скопировано" is too heavy a UX hit for an
    /// action this minor.
    func copyMyCodeToPasteboard() {
        let code = referralService.getMyCode()
        UIPasteboard.general.string = code
        showToast(message: "Скопировано")
    }

    func handleApplyFriendCodeTapped() {
        guard let input = friendCodeInput else { return }
        let raw = input.textField.text ?? ""
        do {
            let credited = try referralService.applyFriendCode(raw)
            input.error = nil
            input.hint = "Бонус +\(Int(credited)) ₽ зачислен"
            input.textField.isEnabled = false
            input.textField.resignFirstResponder()
            // Friend-input cell needs a re-layout to flip the apply button
            // to disabled — the simplest path is a section reload.
            tableView.reloadSections(IndexSet(integer: Section.referral.rawValue), with: .automatic)
            showToast(message: "Бонус начислен")
        } catch let error as ReferralService.ApplyError {
            input.error = error.errorDescription
        } catch {
            input.error = "Не удалось применить код"
        }
    }

    /// Presents a brief auto-dismissing toast pinned to the bottom safe-area.
    /// Lives on the keyWindow so it survives a pushed VC transition and can't
    /// be cropped by the navigation bar.
    func showToast(message: String) {
        let candidateWindow = view.window ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let window = candidateWindow else { return }

        let toast = SettingsToastLabel()
        toast.text = message
        toast.font = AppTypography.body
        toast.textColor = .white
        toast.backgroundColor = UIColor.label.withAlphaComponent(0.9)
        toast.textAlignment = .center
        toast.layer.cornerRadius = AppRadius.sm
        toast.layer.masksToBounds = true
        toast.alpha = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toast.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.xl
            ),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])

        UIView.animate(
            withDuration: 0.2,
            animations: { toast.alpha = 1 },
            completion: { _ in
                UIView.animate(
                    withDuration: 0.3,
                    delay: 1.1,
                    options: [],
                    animations: { toast.alpha = 0 },
                    completion: { _ in toast.removeFromSuperview() }
                )
            }
        )
    }
}

// MARK: - UITextFieldDelegate (referral input)

extension SettingsViewController: UITextFieldDelegate {

    /// "Done" key dismisses the keyboard rather than triggering Apply — the
    /// user typically wants to review their input before committing.
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    /// Force-uppercase + cap at 6 chars as the user types so the value
    /// displayed always matches what `applyFriendCode` will see post-
    /// normalisation. Without the cap nothing prevents pasting a 30-char
    /// blob that would later fail validation with no visible cause.
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let current = textField.text ?? ""
        guard let swiftRange = Range(range, in: current) else { return false }
        let proposed = current.replacingCharacters(in: swiftRange, with: string).uppercased()
        if proposed.count > 6 { return false }
        textField.text = proposed
        return false
    }
}

// MARK: - SettingsToastLabel

/// Small UILabel subclass that bakes 16/8 padding into its intrinsic size so
/// the toast pill renders without an external container. Inline because no
/// other screen uses it yet — promote to its own file if a second caller
/// shows up.
final class SettingsToastLabel: UILabel {
    private let inset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: inset))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + inset.left + inset.right,
            height: size.height + inset.top + inset.bottom
        )
    }
}
