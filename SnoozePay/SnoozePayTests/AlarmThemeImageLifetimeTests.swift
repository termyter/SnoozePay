import UIKit
import XCTest
@testable import SnoozePay

final class AlarmThemeImageLifetimeTests: XCTestCase {
    private var directory: URL!
    private var session: AlarmThemeImageStore.Session!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemeImageLifetime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = AlarmThemeImageStore.Session()
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
        session = nil
        try super.tearDownWithError()
    }

    func testUnsavedImageCreatedBeforeTheCheckedReadSurvives() throws {
        let picked = try saveImage()
        let bytes = try Data(contentsOf: picked)
        let orphan = try oldFile("orphan.jpg")

        XCTAssertTrue(AlarmThemeImageStore.reconcile(in: directory, session: session, readingAlarms: { [] }))

        XCTAssertEqual(try Data(contentsOf: picked), bytes)
        XCTAssertNotNil(AlarmThemeImageStore.loadImage(at: picked))
        XCTAssertFalse(exists(orphan))
    }

    func testImageCreatedAfterAnOldSnapshotSurvivesWithoutAnAlarmSave() throws {
        let orphan = try oldFile("orphan.jpg")
        var picked: URL?
        let didSweep = AlarmThemeImageStore.reconcile(in: directory, session: session) {
            let oldSnapshot: [Alarm] = []
            picked = try self.saveImage()
            return oldSnapshot
        }

        XCTAssertTrue(didSweep)
        XCTAssertNotNil(AlarmThemeImageStore.loadImage(at: try XCTUnwrap(picked)))
        XCTAssertFalse(exists(orphan))
    }

    func testImageSavedToTheRealRepositoryAfterTheSweepSnapshotSurvives() throws {
        let suite = "test.themeImageLifetime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())
        let orphan = try oldFile("orphan.jpg")
        var savedID: UUID?
        var picked: URL?

        let didSweep = AlarmThemeImageStore.reconcile(in: directory, session: session) {
            let oldSnapshot = try repository.fetchAllChecked()
            let url = try self.saveImage()
            let alarm = Alarm(enabled: false, theme: .custom(imagePath: url))
            XCTAssertTrue(repository.save(alarm))
            savedID = alarm.id
            picked = url
            return oldSnapshot
        }

        XCTAssertTrue(didSweep)
        let url = try XCTUnwrap(picked)
        let reopened = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())
        XCTAssertEqual(try reopened.fetchChecked(id: XCTUnwrap(savedID))?.theme, .custom(imagePath: url))
        XCTAssertNotNil(AlarmThemeImageStore.loadImage(at: url))
        XCTAssertFalse(exists(orphan))
    }

    func testRepeatedSweepsKeepNewSelectionsButFreshSessionReclaimsAbandonedOnes() throws {
        let first = try saveImage()
        let second = try saveImage()
        XCTAssertNotEqual(first, second)
        for _ in 0..<2 {
            AlarmThemeImageStore.reconcile(in: directory, referencedURLs: [], session: session)
            XCTAssertTrue(exists(first))
            XCTAssertTrue(exists(second))
        }

        let nextProcess = AlarmThemeImageStore.Session()
        AlarmThemeImageStore.reconcile(in: directory, referencedURLs: [second], session: nextProcess)
        XCTAssertFalse(exists(first))
        XCTAssertTrue(exists(second))
        AlarmThemeImageStore.reconcile(in: directory, referencedURLs: [], session: nextProcess)
        XCTAssertFalse(exists(second))
    }

    func testUnreadableStorePreservesOldAndNewPhotosWithoutRunningDeletion() throws {
        let old = try oldFile("old.jpg")
        let picked = try saveImage()
        let oldBytes = try Data(contentsOf: old)
        let newBytes = try Data(contentsOf: picked)

        let didSweep = AlarmThemeImageStore.reconcile(in: directory, session: session) {
            throw NSError(domain: "ThemeImageLifetime.read", code: 1)
        }

        XCTAssertFalse(didSweep)
        XCTAssertEqual(try Data(contentsOf: old), oldBytes)
        XCTAssertEqual(try Data(contentsOf: picked), newBytes)
    }

    func testFailedWriteLeavesPreviousImageAndDoesNotDisableOldOrphanCleanup() throws {
        let previous = try oldFile("previous.jpg")
        let orphan = try oldFile("orphan.jpg")
        let absentDirectory = directory.appendingPathComponent("does-not-exist", isDirectory: true)

        XCTAssertNil(AlarmThemeImageStore.saveImage(image(), in: absentDirectory, session: session))
        AlarmThemeImageStore.reconcile(in: directory, referencedURLs: [previous], session: session)

        XCTAssertEqual(try Data(contentsOf: previous), Data("old image".utf8))
        XCTAssertFalse(exists(orphan))
    }

    func testProductionSessionDefaultsAlsoProtectANewImage() throws {
        let picked = try XCTUnwrap(AlarmThemeImageStore.saveImage(image(), in: directory))

        XCTAssertTrue(AlarmThemeImageStore.reconcile(in: directory, readingAlarms: { [] }))

        XCTAssertNotNil(AlarmThemeImageStore.loadImage(at: picked))
    }

    func testWriteStartedDuringADeletionCompletesAndRemainsProtected() throws {
        let folder = try XCTUnwrap(directory)
        let orphan = try oldFile("orphan.jpg")
        let picked = folder.appendingPathComponent("alarm-theme-during-cleanup.jpg")
        let bytes = try XCTUnwrap(image().jpegData(compressionQuality: 0.85))
        let deletionEntered = DispatchSemaphore(value: 0)
        let writeAttempted = DispatchSemaphore(value: 0)
        let written = expectation(description: "write completed")
        let controlledSession = AlarmThemeImageStore.Session { url in
            deletionEntered.signal()
            guard writeAttempted.wait(timeout: .now() + 5) == .success else {
                throw NSError(domain: "ThemeImageLifetime.deletionBarrier", code: 1)
            }
            try FileManager.default.removeItem(at: url)
        }

        DispatchQueue.global().async {
            XCTAssertEqual(deletionEntered.wait(timeout: .now() + 5), .success)
            writeAttempted.signal()
            do {
                try controlledSession.write(bytes, to: picked)
            } catch {
                XCTFail("Image write failed: \(error)")
            }
            written.fulfill()
        }
        AlarmThemeImageStore.reconcile(in: folder, referencedURLs: [], session: controlledSession)
        wait(for: [written], timeout: 5)

        XCTAssertFalse(exists(orphan))
        XCTAssertEqual(try Data(contentsOf: picked), bytes)
        writeAttempted.signal()
        AlarmThemeImageStore.reconcile(in: folder, referencedURLs: [], session: controlledSession)
        XCTAssertEqual(try Data(contentsOf: picked), bytes)
        XCTAssertNotNil(AlarmThemeImageStore.loadImage(at: picked))
    }

    private func saveImage() throws -> URL {
        try XCTUnwrap(AlarmThemeImageStore.saveImage(image(), in: directory, session: session))
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func oldFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("old image".utf8).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private final class NoopScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }
}
