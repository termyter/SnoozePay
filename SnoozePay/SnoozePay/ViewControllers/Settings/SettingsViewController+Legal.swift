import UIKit

// MARK: - Legal VC
//
// Pushed by `SettingsViewController` for the "Privacy" / "Terms" rows in the
// `.info` section. Extracted from the host file (#182) to keep it under the
// SwiftLint `file_length` cap; behaviour is unchanged.

/// Simple text placeholder view controller — the actual legal documents
/// will land before App Store submission.
final class LegalViewController: UIViewController {

    private let legalTitle: String

    init(title: String) {
        self.legalTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = legalTitle
        view.backgroundColor = AppColors.bg0

        let textView = UITextView()
        textView.text = Localized.format("settings.legal.body", legalTitle)
        textView.font = AppTypography.body
        textView.textColor = AppColors.fg1
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
