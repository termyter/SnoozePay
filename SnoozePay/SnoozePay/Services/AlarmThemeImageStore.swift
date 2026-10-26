import UIKit
import os

/// Persists user-picked photos for `AlarmTheme.custom` (#151).
///
/// Images land in `Caches/AlarmThemes/` rather than `Documents/` because they
/// are derived assets — the source of truth lives in Photos and the user can
/// always re-pick. Caches survives normal launches but the OS may purge under
/// disk pressure; if that happens the firing screen falls back to the Dawn
/// gradient via `themedBackgroundFactory`.
enum AlarmThemeImageStore {

    private static let log = OSLog(subsystem: AppLogger.subsystem, category: "AlarmThemeImageStore")
    private static let directoryName = "AlarmThemes"
    private static let jpegQuality: CGFloat = 0.85
    private static let processSession = Session()

    /// A picked photo can belong to an unsaved form, so the repository alone
    /// cannot prove it is an orphan. Keep this process's writes until the next
    /// launch. The lock covers both registration and each sweep deletion.
    nonisolated final class Session: @unchecked Sendable {
        private let lock = NSLock()
        private var pickedURLs = Set<URL>()

        func write(_ data: Data, to url: URL) throws {
            lock.lock()
            defer { lock.unlock() }
            try data.write(to: url, options: .atomic)
            pickedURLs.insert(url.standardizedFileURL)
        }

        func removeIfNotPicked(_ url: URL) {
            lock.lock()
            defer { lock.unlock() }
            guard !pickedURLs.contains(url.standardizedFileURL) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Resolve (and create on first use) the on-disk directory holding all
    /// custom theme images. Returned URL has a trailing slash via
    /// `appendingPathComponent(_:isDirectory:)`.
    static func directoryURL() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = caches.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Encode `image` as JPEG and write it under a fresh UUID filename so the
    /// caller can safely keep the previous image around (e.g. for an undo
    /// flow) without us overwriting it. Returns the absolute file URL on
    /// success or nil if encoding / disk write fails — the picker degrades
    /// the failure into "stay on the previous theme" rather than crashing.
    static func saveImage(_ image: UIImage) -> URL? {
        saveImage(image, in: nil)
    }

    /// Directory and session seams keep tests away from the app's real cache.
    static func saveImage(_ image: UIImage, in directory: URL?, session: Session? = nil) -> URL? {
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            os_log("Failed to encode picked image as JPEG", log: log, type: .error)
            return nil
        }
        do {
            let folder = try directory ?? directoryURL()
            let filename = "alarm-theme-\(UUID().uuidString).jpg"
            let fileURL = folder.appendingPathComponent(filename)
            try (session ?? processSession).write(data, to: fileURL)
            return fileURL
        } catch {
            os_log("Failed to write picked image: %{public}@", log: log, type: .error, String(describing: error))
            return nil
        }
    }

    /// Load a previously persisted image. Returns nil when the file is gone
    /// (Caches purge) or cannot be decoded — the caller is responsible for
    /// falling back to a default theme.
    static func loadImage(at url: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Best-effort delete of a single persisted image. Silent on failure — a
    /// missing or already-purged file is not an error for cleanup callers.
    static func deleteImage(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Sweep `directory`, deleting every `alarm-theme-*.jpg` not present in
    /// `referencedURLs` (#357). Because `saveImage` writes a fresh UUID file on
    /// every pick and nothing deletes the old one, re-picking a custom photo or
    /// deleting a `.custom`-themed alarm orphans its JPEG forever. Reconciling
    /// against the live alarm set on launch reclaims both orphan sources in one
    /// place. The launch worker can overlap a new form, so this process's
    /// successful writes are protected even before an alarm references them.
    /// Abandoned selections become ordinary orphans on the next launch.
    ///
    /// Files are matched by `lastPathComponent` so a path that round-tripped
    /// through `URL(string:)` (how `.custom` persists, see `AlarmTheme`) still
    /// matches the file on disk regardless of `file://` vs raw-path spelling.
    /// Exposed with an explicit `directory` so tests can drive a temp folder.
    static func reconcile(in directory: URL, referencedURLs: Set<URL>, session: Session? = nil) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        let keep = Set(referencedURLs.map { $0.lastPathComponent })
        for file in files where !keep.contains(file.lastPathComponent) {
            (session ?? processSession).removeIfNotPicked(file)
        }
    }

    /// Reconcile the real Caches theme directory against the currently
    /// referenced custom images. No-op if the directory can't be resolved
    /// (e.g. first launch before any photo was ever saved).
    static func reconcileCaches(referencedURLs: Set<URL>) {
        guard let directory = try? directoryURL() else { return }
        reconcile(in: directory, referencedURLs: referencedURLs)
    }

    /// The `keep` set for a sweep: every image URL still referenced by a
    /// `.custom` theme in `alarms`.
    static func referencedImageURLs(in alarms: [Alarm]) -> Set<URL> {
        Set(alarms.compactMap { alarm -> URL? in
            if case .custom(let url) = alarm.theme { return url }
            return nil
        })
    }

    /// Sweep driven by a **checked** alarm read (#271).
    ///
    /// The lossy `fetchAll()` collapses a decode failure into `[]`, and `[]`
    /// here does not mean "read failed" — it means "no alarm references any
    /// image", i.e. delete every custom theme JPEG on disk. That would turn a
    /// transient, recoverable decode glitch into permanent photo loss, so an
    /// unreadable store skips the sweep entirely and leaves the files for a
    /// later launch that can read the alarms.
    /// - Returns: `true` when a sweep ran, `false` when it was skipped.
    @discardableResult
    static func reconcile(
        in directory: URL,
        session: Session? = nil,
        readingAlarms read: () throws -> [Alarm]
    ) -> Bool {
        guard let alarms = try? read() else {
            os_log("Theme-image sweep skipped: alarm store unreadable", log: log, type: .error)
            return false
        }
        reconcile(in: directory, referencedURLs: referencedImageURLs(in: alarms), session: session)
        return true
    }

    /// `reconcile(in:readingAlarms:)` against the real Caches directory.
    @discardableResult
    static func reconcileCaches(readingAlarms read: () throws -> [Alarm]) -> Bool {
        guard let directory = try? directoryURL() else { return false }
        return reconcile(in: directory, readingAlarms: read)
    }
}
