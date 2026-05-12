import UIKit

/// Bottom-sheet confirmation for destructive "Удалить будильник" (#163 / V2).
///
/// Replaces the UIAlertController-based action sheet so the destructive flow
/// matches the SP design system (caps + h2 + meta + pain CTA). Presented
/// modally with `.pageSheet` / `.formSheet` detents so the card slides up
/// from the bottom edge of the create-alarm form.
///
/// Layout mirrors `SPMore2.jsx` lines 224-248 (`ConfirmDelete()`):
///   - 64×64 pain-tinted square with X icon
///   - h2 "Удалить будильник?" title
///   - body copy line
///   - `SPButton(.pain, .lg)` "Удалить"
///   - `SPButton(.quiet, .md)` "Отмена"
final class ConfirmDeleteAlarmViewController: UIViewController {

    // MARK: - Callbacks

    /// Invoked after the user taps "Удалить". The host VC handles the actual
    /// delete + repository wiring; this sheet only owns the confirmation UI.
    var onConfirm: (() -> Void)?

    // MARK: - Body copy

    /// Subtitle line shown below the headline. Defaults to the V2 copy "Деньги
    /// с баланса не вернутся. Это безвозвратно."; the host can override to
    /// surface alarm-specific context (name + repeat + time).
    private let bodyCopy: String

    // MARK: - UI

    private let card: SPCard = {
        let card = SPCard(tone: .raised, padding: AppSpacing.sp6, cornerRadius: AppRadius.xl)
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()

    private let iconBadge: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.md
        view.layer.masksToBounds = true
        view.backgroundColor = AppColors.pain500.withAlphaComponent(0.14)
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColors.pain500.withAlphaComponent(0.30).cgColor
        return view
    }()

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "xmark")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)
        )
        let view = UIImageView(image: image)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = AppColors.pain400
        view.contentMode = .center
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.h2
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Удалить будильник?"
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.body
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let deleteButton = SPButton(
        title: "Удалить",
        variant: .pain,
        size: .lg,
        fullWidth: true
    )

    private let cancelButton = SPButton(
        title: "Отмена",
        variant: .quiet,
        size: .md,
        fullWidth: true
    )

    // MARK: - Init

    /// - Parameters:
    ///   - body: Subtitle copy. Defaults to the V2 spec text. Pass a tailored
    ///     line (e.g. "Будни · Пн–Пт · 7:00") when the alarm context is rich.
    ///   - onConfirm: Closure invoked on the destructive tap. The sheet
    ///     dismisses itself before firing the callback.
    init(
        body: String = "Деньги с баланса не вернутся. Это безвозвратно.",
        onConfirm: (() -> Void)? = nil
    ) {
        self.bodyCopy = body
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        // Custom presentation — slide up from the bottom on phones, render as
        // a centred form sheet on iPad / large screens.
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.preferredCornerRadius = AppRadius.xl
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        bodyLabel.text = bodyCopy
        setupUI()
        deleteButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(card)

        iconBadge.addSubview(iconView)
        card.addSubview(iconBadge)
        card.addSubview(titleLabel)
        card.addSubview(bodyLabel)
        card.addSubview(deleteButton)
        card.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: AppSpacing.sp3),
            card.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -AppSpacing.sp3),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),

            iconBadge.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            iconBadge.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconBadge.widthAnchor.constraint(equalToConstant: 64),
            iconBadge.heightAnchor.constraint(equalToConstant: 64),

            iconView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconBadge.bottomAnchor, constant: AppSpacing.sp4),
            titleLabel.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: AppSpacing.sp2),
            bodyLabel.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),

            deleteButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: AppSpacing.sp5),
            deleteButton.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),

            cancelButton.topAnchor.constraint(equalTo: deleteButton.bottomAnchor, constant: AppSpacing.sp2),
            cancelButton.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func confirmTapped() {
        // Dismiss first so the host's onDelete + dismiss(animated:) chain
        // doesn't race with the sheet's own dismissal animation.
        dismiss(animated: true) { [weak self] in
            self?.onConfirm?()
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}
