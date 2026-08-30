import UIKit

// MARK: - Referral cells & actions
//
// Lifted out of `SettingsViewController.swift` so the parent file stays under
// the swiftlint file_length error threshold (issue #144). The stored-property
// surface (`friendCodeInput`, `referralService`, `ReferralRow`) lives on the
// main class because Swift forbids stored properties in extensions; everything
// else is a pure function over those properties and slots into this file.

extension SettingsViewController {

    /// The only gate on the referral section, as a pure function of the flag
    /// so BOTH positions can be laid out on a real table.
    ///
    /// Reading `AppFeatureFlags.referralEnabled` inline here is what made the
    /// on-position untestable: it is a `let` shipping `false`, so the two
    /// tests that wanted it had to `XCTSkipUnless` and never ran, and
    /// reversibility — the whole promise of #676 — rested on helpers
    /// production never called. Invert this `filter` and the suite goes red.
    ///
    /// The archaeology behind hiding rather than emptying — the 17.33pt
    /// phantom footer, why `heightForFooterInSection` cannot take it back,
    /// and why `.diagnostics` is treated differently (#684) — lives on
    /// `ReferralEntryPointVisibilityTests`, next to the assertions that
    /// measure it.
    static func visibleSections(referralEnabled: Bool) -> [Section] {
        Section.allCases.filter { $0 != .referral || referralEnabled }
    }

    /// The sections the table is currently showing, in order. A table section
    /// INDEX is a position in this array, not a `Section` raw value.
    var visibleSections: [Section] {
        Self.visibleSections(referralEnabled: referralEnabled)
    }

    // The `.referral` section's rows and header are plain constants in
    // `SettingsViewController`, not functions of the flag. They used to be
    // `referralRowCount(referralEnabled:)` / `referralSectionTitle(...)`,
    // gated a second time inside a `switch` that
    // `visibleSections(referralEnabled:)` had already filtered. The off-branch
    // was unreachable in production and the two tests pinning it were green
    // against code that never ran (#676). One gate, in `visibleSections`,
    // tested on a live table in both positions.

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
        cell.configure(text: "За каждого друга — +\(MoneyFormatter.string(200)) на ваш баланс")
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
            input.hint = "Бонус +\(MoneyFormatter.string(credited)) зачислен"
            input.textField.isEnabled = false
            input.textField.resignFirstResponder()
            // Friend-input cell needs a re-layout to flip the apply button
            // to disabled — the simplest path is a section reload.
            // A table index, not a raw value: `.referral` is index 3 only
            // while it is visible, and this path is reachable only then.
            if let index = visibleSections.firstIndex(of: .referral) {
                tableView.reloadSections(IndexSet(integer: index), with: .automatic)
            }
            showToast(message: "Бонус начислен")
        } catch let error as ReferralService.ApplyError {
            input.error = error.errorDescription
        } catch {
            input.error = "Не удалось применить код"
        }
    }

    /// Presents a brief auto-dismissing toast above the tab bar. Lives on the
    /// keyWindow so it survives a pushed VC transition and can't be cropped by
    /// the navigation bar; `SettingsToastLayout` owns where exactly it lands.
    func showToast(message: String) {
        let candidateWindow = view.window ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let window = candidateWindow else { return }

        let toast = SettingsToastLabel()
        toast.text = message
        toast.alpha = 0
        SettingsToastLayout.install(toast, in: window)

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
    ///
    /// We always return `false` and rewrite the text ourselves (the uppercase
    /// transform means the rendered string differs from the raw replacement),
    /// but we recompute the caret offset and restore it via
    /// `selectedTextRange` so mid-string edits and backspaces don't jump the
    /// caret to the end. The transform itself lives in `ReferralCodeInput`
    /// so it can be unit-tested without a live `UITextField`.
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let current = textField.text ?? ""
        guard let result = ReferralCodeInput.transform(
            current: current,
            replacing: range,
            with: string
        ) else { return false }

        textField.text = result.text
        // Map the UTF-16 caret offset back onto a live text position. Clamp to
        // the document end in case the transform produced a shorter string.
        let offset = min(result.caretOffset, (result.text as NSString).length)
        if let position = textField.position(from: textField.beginningOfDocument, offset: offset) {
            textField.selectedTextRange = textField.textRange(from: position, to: position)
        }
        return false
    }
}

// MARK: - ReferralCodeInput (pure transform)

/// Pure, UI-free transform behind the referral input's `shouldChangeCharactersIn`
/// delegate hook. Extracted so the uppercase + 6-char-cap + caret math can be
/// unit-tested without instantiating a `UITextField`.
enum ReferralCodeInput {

    /// Result of applying an edit: the new field text plus where the caret
    /// should land, expressed as a UTF-16 offset from the start of the string.
    struct Result: Equatable {
        let text: String
        let caretOffset: Int
    }

    /// Applies the replacement, uppercases the whole value, and rejects (returns
    /// `nil`) any edit that would push the result past 6 characters. On accept,
    /// the caret offset is the original range start plus the length of the
    /// inserted (uppercased) text — i.e. it follows what the user just typed,
    /// even mid-string.
    static func transform(current: String, replacing range: NSRange, with string: String) -> Result? {
        guard let swiftRange = Range(range, in: current) else { return nil }
        let proposed = current.replacingCharacters(in: swiftRange, with: string).uppercased()
        if proposed.count > 6 { return nil }
        let insertedLength = (string.uppercased() as NSString).length
        let caretOffset = range.location + insertedLength
        return Result(text: proposed, caretOffset: caretOffset)
    }
}

// MARK: - SettingsToastLayout

/// Where the toast lands. Split out of `showToast` so the geometry can be
/// asserted without waiting out the 1.5-second animation.
enum SettingsToastLayout {

    /// Gap between the toast and whatever edge it sits above.
    static let gap = AppSpacing.sp3

    /// The tab bar the toast has to clear, if one is actually on screen.
    ///
    /// Resolved from the *window* rather than from a view controller's
    /// `tabBarController`: the toast is a window subview, so the window is what
    /// it has to negotiate with, and that answer stays right for a pushed VC, a
    /// presented one and the DEBUG tour mounts alike. Returns `nil` when the
    /// bar is hidden or parked off-screen — `hidesBottomBarWhenPushed` slides
    /// the bar out of the window instead of hiding it, and anchoring to a bar
    /// parked below the screen would drag the toast off with it.
    static func obstructingTabBar(in window: UIWindow) -> UITabBar? {
        var controller = window.rootViewController
        var candidate: UITabBar?
        while let current = controller {
            if let tabs = current as? UITabBarController {
                candidate = tabs.tabBar
            }
            controller = current.presentedViewController
        }
        guard let bar = candidate, bar.window === window, !bar.isHidden, bar.alpha > 0 else {
            return nil
        }
        return window.bounds.intersects(bar.convert(bar.bounds, to: window)) ? bar : nil
    }

    /// Adds `toast` to `window` and pins it above the tab bar when there is
    /// one, else above the bottom safe area.
    ///
    /// Anchoring to the bar's own `topAnchor` rather than to a constant is the
    /// point: the bar's height is UIKit's to decide (it differs with the
    /// home-indicator inset, and again in a compact layout), so a hand-measured
    /// offset is right on one device and wrong on the next. The window is a
    /// common ancestor of both views, and `UITabBar` translates its frame into
    /// the layout engine, so the cross-branch constraint resolves cleanly.
    static func install(_ toast: UIView, in window: UIWindow) {
        toast.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(toast)

        let bottom: NSLayoutConstraint
        if let bar = obstructingTabBar(in: window) {
            bottom = toast.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -gap)
        } else {
            bottom = toast.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp6
            )
        }

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            bottom,
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsToastLabel.minimumHeight)
        ])
    }
}

// MARK: - SettingsToastLabel

/// Small UILabel subclass that bakes its padding into the intrinsic size so
/// the toast pill renders without an external container. Inline because no
/// other screen uses it yet — promote to its own file if a second caller
/// shows up.
final class SettingsToastLabel: UILabel {

    /// Pill fill. Exposed so `SettingsLightThemeTests` measures the values
    /// actually rendered rather than a copy.
    ///
    /// Third recipe, and the first one that isn't a surface. `.white` on
    /// `UIColor.label`@90% inverted with the theme and drew white on white in
    /// dark (1.24:1, #496); `bg3` fixed the ink but left the pill itself at
    /// 1.19:1 against the light page, so only the border and the glyphs were
    /// holding it (#518). No step of the surface ramp clears 3:1 against the
    /// page in either theme, so the pill is now the INVERSE surface — see the
    /// measurements next to `AppColors.toastSurface`.
    static let fillColor = AppColors.toastSurface
    /// Pill ink — the inverse-surface foreground, which flips together with
    /// `fillColor`. Not `fg1`: that is ink for a normal surface and would land
    /// same-on-same here.
    static let inkColor = AppColors.fgOnToast
    /// Floor height so a one-line toast keeps a pill silhouette.
    static let minimumHeight: CGFloat = AppSpacing.sp8 - AppSpacing.sp1

    private let inset = UIEdgeInsets(
        top: AppSpacing.sp2,
        left: AppSpacing.sp4,
        bottom: AppSpacing.sp2,
        right: AppSpacing.sp4
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = AppTypography.body
        textAlignment = .center
        layer.cornerRadius = AppRadius.sm
        // A shadow can't render through `masksToBounds`; the horizontal inset
        // keeps the glyphs well clear of the rounded corners without clipping.
        layer.masksToBounds = false
        applyThemedDecoration()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (label: SettingsToastLabel, _) in
            label.applyThemedDecoration()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: AppRadius.sm).cgPath
    }

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

    /// Fill, border and shadow all cache a resolved value (`cgColor` for two of
    /// them), so all three re-resolve on a theme flip. The pill floats over
    /// arbitrary content, so it keeps the card recipe — fill + hairline + lift
    /// — even though the inverse fill now carries the separation on its own.
    private func applyThemedDecoration() {
        backgroundColor = Self.fillColor
        textColor = Self.inkColor
        AppShadow.shadow2(for: traitCollection).apply(to: layer)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        layer.borderWidth = 1.0 / scale
        layer.borderColor = AppColors.toastEdge.resolvedColor(with: traitCollection).cgColor
    }
}
