import UIKit

/// V2 progressive-mode preview row showing how penalties double on each
/// snooze. Replaces the prior single-line text version with a mono "50 → 100
/// → 200 → 400 ₽" sequence whose stops gradient from `warn400` (cheap) into
/// `pain400` (painful) — matches `SPScreensV2.jsx` lines 628-638.
final class ProgressivePreviewCell: UITableViewCell {

    static let reuseID = "ProgressivePreviewCell"

    // MARK: - UI

    private let sequenceLabel: UILabel = {
        let label = UILabel()
        label.font = AppFonts.mono(.semibold, 14)
        label.textColor = AppColors.warn400
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = AppColors.bg1
        selectionStyle = .none
        contentView.addSubview(sequenceLabel)
        NSLayoutConstraint.activate([
            sequenceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            sequenceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            sequenceLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),
            sequenceLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.md)
        ])
    }

    // MARK: - Configure

    /// `text` arrives from `CreateAlarmViewModel.progressiveScalePreview` in
    /// the legacy "1-е: 50₽ → 2-е: 100₽ → ..." format. We rebuild the V2
    /// sequence here so the view-model output stays stable while the row's
    /// presentation matches the JSX recipe (gradient stops + mono digits).
    func configure(text: String) {
        // Parse the legacy preview output to recover the integer amounts.
        // Each "1-е: 50₽" stop yields a single digit cluster after the
        // colon — `components(separatedBy: ":")` + digit extraction is
        // robust to the "₽" suffix and arrow separators.
        let amounts: [Int] = text
            .components(separatedBy: " → ")
            .compactMap { stop -> Int? in
                guard let colonIndex = stop.firstIndex(of: ":") else { return nil }
                let tail = stop[stop.index(after: colonIndex)...]
                let digits = tail.unicodeScalars
                    .map { CharacterSet.decimalDigits.contains($0) ? Character($0) : " " }
                let cluster = String(digits).split(separator: " ").first.map(String.init) ?? ""
                return Int(cluster)
            }

        // Defensive: if parsing failed mid-stream, fall back to the raw text.
        guard amounts.count >= 2 else {
            sequenceLabel.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: AppFonts.mono(.semibold, 14),
                    .foregroundColor: AppColors.warn400
                ]
            )
            return
        }

        sequenceLabel.attributedText = Self.makeSequence(amounts: Array(amounts.prefix(4)))
    }

    /// Compose the "50 → 100 → 200 → 400 ₽" attributed sequence. The first
    /// two stops are `warn400`, the third painful, the fourth boldest pain.
    private static func makeSequence(amounts: [Int]) -> NSAttributedString {
        let stopColors: [UIColor] = [
            AppColors.warn400,
            AppColors.warn400,
            AppColors.pain400,
            AppColors.pain400
        ]
        let stopWeights: [AppFonts.Weight] = [.semibold, .semibold, .semibold, .bold]
        let stopSizes: [CGFloat] = [14, 14, 14, 16]
        let arrow = NSAttributedString(
            string: "  →  ",
            attributes: [
                .font: AppFonts.mono(.regular, 14),
                .foregroundColor: AppColors.fg4
            ]
        )
        let composed = NSMutableAttributedString()
        for (index, amount) in amounts.enumerated() {
            let colorIndex = min(index, stopColors.count - 1)
            let isLast = index == amounts.count - 1
            let weight = stopWeights[colorIndex]
            let size = stopSizes[colorIndex]
            let text = isLast ? "\(amount) ₽" : "\(amount)"
            composed.append(NSAttributedString(
                string: text,
                attributes: [
                    .font: AppFonts.mono(weight, size),
                    .foregroundColor: stopColors[colorIndex]
                ]
            ))
            if !isLast {
                composed.append(arrow)
            }
        }
        return composed
    }
}
