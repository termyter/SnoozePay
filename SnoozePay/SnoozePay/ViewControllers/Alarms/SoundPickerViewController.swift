import UIKit
import AudioToolbox

/// Full-screen sound picker pushed onto navigation stack.
/// Shows all available sounds with play preview buttons and checkmark for selection.
final class SoundPickerViewController: UITableViewController {

    // MARK: - Properties

    private let sounds: [(id: String, name: String)]
    private var selectedSoundID: String
    private let onSelect: (String) -> Void
    private let previewSound: (String) -> Void

    private var currentlyPlayingID: String?

    // MARK: - Init

    /// - Parameters:
    ///   - sounds: Available sounds list (id + display name)
    ///   - selectedID: Currently selected sound ID
    ///   - onSelect: Callback when user picks a sound
    ///   - previewSound: Callback to play preview of a sound
    init(
        sounds: [(id: String, name: String)],
        selectedID: String,
        onSelect: @escaping (String) -> Void,
        previewSound: @escaping (String) -> Void
    ) {
        self.sounds = sounds
        self.selectedSoundID = selectedID
        self.onSelect = onSelect
        self.previewSound = previewSound
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Выбор звука"
        view.backgroundColor = AppColors.screenBackground
        tableView.backgroundColor = AppColors.screenBackground
        tableView.register(SoundCell.self, forCellReuseIdentifier: SoundCell.reuseID)
    }

    // MARK: - Table View

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sounds.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        52
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SoundCell.reuseID, for: indexPath
        ) as? SoundCell else {
            return UITableViewCell()
        }

        let sound = sounds[indexPath.row]
        let isSelected = sound.id == selectedSoundID
        cell.configure(name: sound.name, isSelected: isSelected)
        cell.onPlayTapped = { [weak self] in
            self?.previewSound(sound.id)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let sound = sounds[indexPath.row]
        selectedSoundID = sound.id
        onSelect(sound.id)
        previewSound(sound.id)
        tableView.reloadData()
        // Pop back after short delay so user hears the preview
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: - Sound Cell

final class SoundCell: UITableViewCell {

    static let reuseID = "SoundCell"

    var onPlayTapped: (() -> Void)?

    // MARK: - UI

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 17)
        return l
    }()

    private let playButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        b.setImage(UIImage(systemName: "play.circle", withConfiguration: config), for: .normal)
        b.tintColor = AppColors.accentBlue
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let checkmark: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "checkmark")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        iv.tintColor = AppColors.accentBlue
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
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
        backgroundColor = .secondarySystemBackground
        selectionStyle = .default

        contentView.addSubview(nameLabel)
        contentView.addSubview(playButton)
        contentView.addSubview(checkmark)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            checkmark.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            checkmark.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 20),

            nameLabel.leadingAnchor.constraint(equalTo: checkmark.trailingAnchor, constant: AppSpacing.sm),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            playButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            playButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: playButton.leadingAnchor, constant: -AppSpacing.sm)
        ])

        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
    }

    @objc private func playTapped() {
        onPlayTapped?()
    }

    // MARK: - Configure

    func configure(name: String, isSelected: Bool) {
        nameLabel.text = name
        nameLabel.textColor = isSelected ? AppColors.accentBlue : .label
        nameLabel.font = UIFont.systemFont(ofSize: 17, weight: isSelected ? .semibold : .regular)
        checkmark.isHidden = !isSelected
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPlayTapped = nil
        checkmark.isHidden = true
        nameLabel.textColor = .label
        nameLabel.font = UIFont.systemFont(ofSize: 17)
    }
}
