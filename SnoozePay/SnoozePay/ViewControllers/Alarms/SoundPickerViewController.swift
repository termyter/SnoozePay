import UIKit
import AudioToolbox

/// Full-screen sound picker pushed onto the navigation stack.
///
/// Each row uses the SP design-system primitives (`SPRow` + `SPCard` + a
/// `SPButton(.quiet, .sm)` play / pause head) so the screen reads the same
/// as the rest of the brand-refreshed surfaces (#150). The selected row
/// flips to a money-tinted SPCard so the active sound stands out without
/// needing a separate trailing checkmark badge — although the checkmark is
/// kept on the trailing edge per the design spec.
///
/// `onSelect` and `previewSound` callbacks intentionally keep the same
/// signatures as the pre-refresh picker so callers (the alarm form) do not
/// need to change.
final class SoundPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Properties

    private let sounds: [(id: String, name: String)]
    private var selectedSoundID: String
    private let onSelect: (String) -> Void
    private let previewSound: (String) -> Void

    /// `id` of the sound whose preview is currently being broadcast — drives
    /// the "play" / "pause" toggling on the row's head SPButton. Reset by a
    /// short timer keyed to the average preview length so the icon doesn't
    /// stay stuck on `pause.fill` once the system sound finishes.
    private var currentlyPlayingID: String?
    private var previewResetWorkItem: DispatchWorkItem?

    // MARK: - UI

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .clear
        // Generous row spacing keeps consecutive SPCards from visually
        // running into each other — `tableView.separatorInset` doesn't
        // help when each row has its own card chrome.
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        table.contentInset = UIEdgeInsets(
            top: AppSpacing.sp3, left: 0, bottom: AppSpacing.sp4, right: 0
        )
        return table
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - sounds: Available sounds list (id + display name).
    ///   - selectedID: Currently selected sound id.
    ///   - onSelect: Callback fired when the user picks a sound. The picker
    ///     pops itself shortly afterwards so the user hears the preview.
    ///   - previewSound: Callback to play preview for a given sound id.
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
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Выбор звука"
        view.backgroundColor = AppColors.bg0
        setupTableView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        previewResetWorkItem?.cancel()
        previewResetWorkItem = nil
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SoundPickerRowCell.self, forCellReuseIdentifier: SoundPickerRowCell.reuseID)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: AppSpacing.sp4
            ),
            tableView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -AppSpacing.sp4
            ),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - Table view

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sounds.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SoundPickerRowCell.reuseID, for: indexPath
        ) as? SoundPickerRowCell else {
            return UITableViewCell()
        }

        let sound = sounds[indexPath.row]
        let isSelected = sound.id == selectedSoundID
        let isPlaying = sound.id == currentlyPlayingID
        cell.configure(
            name: sound.name,
            duration: Self.previewDuration(for: sound.id),
            isSelected: isSelected,
            isPlaying: isPlaying
        )
        cell.onPlayTapped = { [weak self] in
            self?.handlePreviewToggle(for: sound.id)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let sound = sounds[indexPath.row]
        selectedSoundID = sound.id
        onSelect(sound.id)
        previewSound(sound.id)
        tableView.reloadData()
        // Pop back after a short delay so the user hears the chosen preview
        // before the picker disappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - Preview handling

    /// Toggle preview playback on the row's "play" / "pause" head. We don't
    /// have a real audio session for previews (the live alarm sound is what
    /// uses the AVAudioSession) — system sounds fire-and-forget, so the
    /// "pause" state is a UI affordance backed by a timer that resets the
    /// icon when the typical preview length elapses.
    private func handlePreviewToggle(for soundID: String) {
        previewResetWorkItem?.cancel()

        if currentlyPlayingID == soundID {
            // Tap on the same row → cancel the visual "playing" state.
            // System sounds can't actually be stopped mid-play, but the
            // icon flip honours the user's intent.
            currentlyPlayingID = nil
            tableView.reloadData()
            return
        }

        currentlyPlayingID = soundID
        previewSound(soundID)
        tableView.reloadData()

        // Auto-reset the play state after the configured preview length
        // so the row icon reverts to "play" once the system sound has
        // realistically finished.
        let duration = Self.previewDurationSeconds(for: soundID)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.currentlyPlayingID == soundID else { return }
            self.currentlyPlayingID = nil
            self.tableView.reloadData()
        }
        previewResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    // MARK: - Preview duration metadata

    /// Approximate preview length per sound id. Used both for the
    /// "0:42" subtitle copy and the visual reset timer. Numbers are
    /// hand-tuned against the AudioToolbox `SystemSoundID` table — the
    /// production soundbank will eventually ship real durations on the
    /// alarm-sound model itself.
    private static let previewDurations: [String: Double] = [
        "dawn": 6,
        "radar": 4,
        "drops": 2,
        "piano": 3,
        "guitar": 3,
        "bell": 2,
        "waves": 8,
        "birds": 6,
        "classic": 5,
        "jazz": 5
    ]

    private static func previewDurationSeconds(for soundID: String) -> Double {
        previewDurations[soundID] ?? 3
    }

    private static func previewDuration(for soundID: String) -> String {
        let total = Int(previewDurationSeconds(for: soundID))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// `SoundPickerRowCell` lives in
// `ViewControllers/Alarms/Cells/SoundPickerRowCell.swift` so this file stays
// under the SwiftLint `file_length` cap.
