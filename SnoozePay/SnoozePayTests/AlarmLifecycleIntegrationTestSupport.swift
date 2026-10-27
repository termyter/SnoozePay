import AlarmKit
import XCTest
@testable import SnoozePay

/// Framework-free native inventory shared by combined lifecycle regressions.
/// It supplies complete projections and never constructs an AlarmKit.Alarm.
@available(iOS 26.0, *)
@MainActor
final class LifecycleNativeInventory {
    var entries: [NativeOccurrenceSnapshot]
    var blockedCancellation: Set<UUID> = []
    var onOccurrenceRead: (() -> Void)?
    var onRegisteredRead: (() -> Void)?
    private(set) var occurrenceReads = 0
    private(set) var registeredReads = 0
    private(set) var cancelled: [UUID] = []
    private(set) var stopped: [UUID] = []

    init(entries: [NativeOccurrenceSnapshot] = []) { self.entries = entries }

    lazy var backend = AlarmKitScheduler(
        cancelAlarm: { [unowned self] id in
            cancelled.append(id)
            if !blockedCancellation.contains(id) { entries.removeAll { $0.id == id } }
        },
        readAuthorization: { .authorized },
        stopAlarm: { [unowned self] id in stopped.append(id) },
        readOccurrenceSnapshots: { [unowned self] in
            occurrenceReads += 1
            onOccurrenceRead?()
            return entries
        },
        readRegisteredAlarmIDs: { [unowned self] in
            registeredReads += 1
            onRegisteredRead?()
            return Set(entries.map(\.id))
        }
    )
}
