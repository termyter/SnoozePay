import CryptoKit
import Foundation
import OSLog
import os
import XCTest
@testable import SnoozePay

/// One current-process observation, not a flush guarantee or coverage of every logger mapping.
@MainActor
final class AppLoggerPublicWriterObservationTests: XCTestCase {
    func testRealSchedulerErrorEmissionIsObservedInCurrentProcessWithoutSink() async throws {
        let input = PublicWriterInput(
            nonce: "SNOOZEPAY-744-PUBLIC-WRITER-SENTINEL:" + UUID().uuidString,
            processID: Int(ProcessInfo.processInfo.processIdentifier),
            bundleID: Bundle.main.bundleIdentifier,
            bundleIsApp: Bundle.main.bundleURL.pathExtension == "app",
            packageIsApp: Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
            cancelledAtStart: Task<Never, Never>.isCancelled
        )
        let worker = Task.detached(priority: .utility) { PublicWriterObserver.observe(input) }
        let proof = await withTaskCancellationHandler(operation: {
            await worker.value
        }, onCancel: {
            worker.cancel()
        })
        record(proof)
        XCTAssertFalse(Task<Never, Never>.isCancelled)
        XCTAssertFalse(proof.parentWasCancelledAtStart)
        XCTAssertEqual(proof.workerCancelledAtFinish, false)
        XCTAssertEqual(proof.status, "REAL_WRITER_OBSERVED", "Only safe scalar observation proof is retained")
        XCTAssertFalse(proof.workerWasMainThread)
        XCTAssertTrue(proof.hostVerified)
        XCTAssertEqual(proof.processID, proof.workerProcessID)
        XCTAssertEqual(proof.sinkBeforeBaseline, true)
        XCTAssertEqual(proof.sinkBeforeEmit, true)
        XCTAssertEqual(proof.sinkAfterObservation, true)
        XCTAssertEqual(proof.emitCallCount, 1)
        let baseline = try XCTUnwrap(proof.baseline)
        XCTAssertEqual(baseline.status, "EMPTY_COMPLETE")
        XCTAssertEqual(baseline.objectsRead, 0)
        XCTAssertEqual(baseline.exhausted, true)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(proof.emitStarted), try XCTUnwrap(baseline.returned))
        XCTAssertLessThanOrEqual(try XCTUnwrap(proof.emitCompleted), 5)
        XCTAssertFalse(proof.postReads.isEmpty)
        XCTAssertLessThanOrEqual(proof.postReads.count, 21)
        XCTAssertTrue(proof.postReads.allSatisfy {
            guard let count = $0.objectsRead else { return false }
            return count >= 0 && count <= 32
        })
        XCTAssertTrue(zip(proof.postReads, proof.postReads.dropFirst()).allSatisfy {
            guard let completed = $0.0.returned, let started = $0.1.started else { return false }
            return started - completed >= 0.25
        })
        let accepted = try XCTUnwrap(proof.postReads.last)
        XCTAssertEqual(accepted.status, "ONE_COMPLETE")
        XCTAssertEqual(accepted.exhausted, true)
        XCTAssertEqual(accepted.objectsRead, 1)
        XCTAssertEqual(accepted.typedLog, true)
        XCTAssertLessThanOrEqual(try XCTUnwrap(accepted.returned), 5)
        let row = try XCTUnwrap(accepted.entry)
        XCTAssertTrue(row.messageEqual)
        XCTAssertEqual(row.messageSHA256, proof.nonceSHA256)
        XCTAssertEqual(row.processID, proof.processID)
        XCTAssertEqual(row.subsystemSHA256, proof.expectedSubsystemSHA256)
        XCTAssertEqual(row.categorySHA256, PublicWriterObserver.digest("Scheduler"))
        XCTAssertEqual(row.levelRaw, OSLogEntryLog.Level.error.rawValue)
        XCTAssertTrue(row.isError)
        XCTAssertTrue(row.date.isFinite && row.date >= proof.wallLower && row.date <= proof.wallUpper)
        XCTAssertTrue(proof.finished.isFinite && proof.finished >= 0 && proof.finished <= 5)
        XCTAssertTrue(proof.finishedWall.isFinite
            && proof.finishedWall >= proof.wallLower && proof.finishedWall <= proof.wallUpper)
    }

    private func record(_ proof: PublicWriterProof) {
        let prefix = "AppLoggerPublicWriterObservation "
        let line: String
        do {
            var payload = proof.payload()
            payload["parentCancelledAtRecord"] = Task<Never, Never>.isCancelled
            payload["actualTestCaseName"] = name
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            line = prefix + (String(data: data, encoding: .utf8)
                ?? "{\"encodingError\":true,\"schema\":1}")
        } catch {
            line = prefix + "{\"encodingError\":true,\"schema\":1}"
        }
        let attachment = XCTAttachment(string: line)
        attachment.name = "AppLogger public writer observation"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(line)
        XCTAssertFalse(line.contains("\"encodingError\":true"), "Safe observation packet encoding failed")
    }
}

private nonisolated struct PublicWriterInput: Sendable {
    let nonce: String
    let processID: Int
    let bundleID: String?
    let bundleIsApp: Bool
    let packageIsApp: Bool
    let cancelledAtStart: Bool
}

private nonisolated struct PublicWriterEntry: Sendable {
    let messageEqual: Bool
    let messageSHA256: String
    let processID: Int
    let subsystemSHA256: String
    let categorySHA256: String
    let knownSubsystem: String?
    let knownCategory: String?
    let levelRaw: Int
    let isError: Bool
    let date: Double

    func payload() -> [String: Any] {
        ["messageEqual": messageEqual, "messageSHA256": messageSHA256, "processID": processID,
         "subsystemSHA256": subsystemSHA256, "categorySHA256": categorySHA256,
         "knownSubsystem": PublicWriterObserver.nullable(knownSubsystem),
         "knownCategory": PublicWriterObserver.nullable(knownCategory),
         "levelRaw": levelRaw, "isError": isError, "dateEpoch": String(describing: date)]
    }
}

private nonisolated struct PublicWriterQuery: Sendable {
    let attempt: Int
    var phase = "UNVISITED"
    var status = "UNVISITED"
    var started: Double?
    var storeCompleted: Double?
    var positionCompleted: Double?
    var queryCreated: Double?
    var iteratorCreated: Double?
    var lastNextCompleted: Double?
    var completed: Double?
    var returned: Double?
    var objectsRead: Int?
    var exhausted: Bool?
    var typedLog: Bool?
    var entry: PublicWriterEntry?
    var errorDomain: String?
    var errorDomainSHA256: String?
    var errorCode: Int?
    var observedMessageSHA256: String?

    func payload() -> [String: Any] {
        ["attempt": attempt, "phase": phase, "status": status,
         "started": PublicWriterObserver.time(started), "storeCompleted": PublicWriterObserver.time(storeCompleted),
         "positionCompleted": PublicWriterObserver.time(positionCompleted),
         "queryCreated": PublicWriterObserver.time(queryCreated),
         "iteratorCreated": PublicWriterObserver.time(iteratorCreated),
         "lastNextCompleted": PublicWriterObserver.time(lastNextCompleted),
         "completed": PublicWriterObserver.time(completed), "returned": PublicWriterObserver.time(returned),
         "objectsRead": PublicWriterObserver.nullable(objectsRead),
         "exhausted": PublicWriterObserver.nullable(exhausted), "typedLog": PublicWriterObserver.nullable(typedLog),
         "entry": PublicWriterObserver.nullable(entry.map { $0.payload() }),
         "errorDomain": PublicWriterObserver.nullable(errorDomain),
         "errorDomainSHA256": PublicWriterObserver.nullable(errorDomainSHA256),
         "errorCode": PublicWriterObserver.nullable(errorCode),
         "observedMessageSHA256": PublicWriterObserver.nullable(observedMessageSHA256)]
    }
}

private nonisolated struct PublicWriterProof: Sendable {
    let workerWasMainThread: Bool
    let processID: Int
    let workerProcessID: Int
    let hostVerified: Bool
    let bundleIsApp: Bool
    let packageIsApp: Bool
    let expectedSubsystemSHA256: String?
    let nonceSHA256: String
    let monotonicStart: Double
    let wallLower: Double
    let wallUpper: Double
    let parentWasCancelledAtStart: Bool
    var status = "UNVISITED"
    var phase = "UNVISITED"
    var sinkBeforeBaseline: Bool?
    var sinkBeforeEmit: Bool?
    var sinkAfterObservation: Bool?
    var sinkBeforeCompleted: Double?
    var sinkBeforeEmitCompleted: Double?
    var sinkAfterCompleted: Double?
    var emitCallCount = 0
    var emitStarted: Double?
    var emitCompleted: Double?
    var baseline: PublicWriterQuery?
    var postReads: [PublicWriterQuery] = []
    var pollGaps: [[Double]] = []
    var finished = Double.nan
    var finishedWall = Double.nan
    var workerCancelledAtFinish: Bool?

    func payload() -> [String: Any] {
        ["schema": 1, "kind": "realCurrentProcessWriterObservation",
         "method": "AppLoggerPublicWriterObservationTests/"
            + "testRealSchedulerErrorEmissionIsObservedInCurrentProcessWithoutSink",
         "status": status, "phase": phase, "budgetSeconds": 5, "minimumPollGapSeconds": 0.25,
         "maxPostReads": 21, "maxObjectsPerQuery": 32, "softDeadlineOnly": true,
         "workerWasMainThread": workerWasMainThread, "processID": processID, "workerProcessID": workerProcessID,
         "hostVerified": hostVerified, "bundleIsApp": bundleIsApp, "packageIsApp": packageIsApp,
         "parentWasCancelledAtStart": parentWasCancelledAtStart,
         "workerCancelledAtFinish": PublicWriterObserver.nullable(workerCancelledAtFinish),
         "expectedSubsystemSHA256": PublicWriterObserver.nullable(expectedSubsystemSHA256),
         "expectedHostSubsystem": "io.mobilife.SnoozePay", "expectedCategory": "Scheduler",
         "expectedErrorLevel": "error", "expectedErrorLevelRaw": OSLogEntryLog.Level.error.rawValue,
         "nonceSHA256": nonceSHA256, "monotonicStart": String(describing: monotonicStart),
         "wallLowerEpoch": String(describing: wallLower), "wallUpperEpoch": String(describing: wallUpper),
         "sinkBeforeBaseline": PublicWriterObserver.nullable(sinkBeforeBaseline),
         "sinkBeforeEmit": PublicWriterObserver.nullable(sinkBeforeEmit),
         "sinkAfterObservation": PublicWriterObserver.nullable(sinkAfterObservation),
         "sinkBeforeCompleted": PublicWriterObserver.time(sinkBeforeCompleted),
         "sinkBeforeEmitCompleted": PublicWriterObserver.time(sinkBeforeEmitCompleted),
         "sinkAfterCompleted": PublicWriterObserver.time(sinkAfterCompleted),
         "emitCallCount": emitCallCount, "emitStarted": PublicWriterObserver.time(emitStarted),
         "emitCompleted": PublicWriterObserver.time(emitCompleted),
         "baseline": PublicWriterObserver.nullable(baseline.map { $0.payload() }),
         "postReads": postReads.map { $0.payload() },
         "pollGaps": pollGaps.map { $0.map { String(describing: $0) } },
         "finished": String(describing: finished), "finishedWallEpoch": String(describing: finishedWall)]
    }
}

private nonisolated struct PublicWriterContext {
    let input: PublicWriterInput
    let monotonicStart: Double
    let wallLower: Double
    let wallUpper: Double
    let subsystem: String
    let nonceSHA256: String

    var elapsed: Double { ProcessInfo.processInfo.systemUptime - monotonicStart }
}

private nonisolated struct PublicWriterStop: Error {
    let status: String
}

private nonisolated enum PublicWriterObserver {
    /// Synchronous and explicitly nonisolated: default MainActor cannot move this detached work onto the UI executor.
    nonisolated static func observe(_ input: PublicWriterInput) -> PublicWriterProof {
        let start = ProcessInfo.processInfo.systemUptime
        let lower = Date().timeIntervalSince1970
        let hostVerified = input.bundleID == "io.mobilife.SnoozePay" && input.bundleIsApp && input.packageIsApp
        var proof = PublicWriterProof(workerWasMainThread: Thread.isMainThread, processID: input.processID,
            workerProcessID: Int(ProcessInfo.processInfo.processIdentifier), hostVerified: hostVerified,
            bundleIsApp: input.bundleIsApp, packageIsApp: input.packageIsApp,
            expectedSubsystemSHA256: input.bundleID.map { digest($0) }, nonceSHA256: digest(input.nonce),
            monotonicStart: start, wallLower: lower, wallUpper: lower + 5,
            parentWasCancelledAtStart: input.cancelledAtStart)
        let context = PublicWriterContext(input: input, monotonicStart: start,
            wallLower: lower, wallUpper: lower + 5, subsystem: input.bundleID ?? "", nonceSHA256: proof.nonceSHA256)
        perform(context, proof: &proof)
        if proof.sinkBeforeBaseline != nil && (try? check(context, afterCall: false)) != nil {
            proof.sinkAfterObservation = AppLogger.testSink == nil
            proof.sinkAfterCompleted = context.elapsed
            if proof.sinkAfterObservation != true {
                proof.status = "SINK_NOT_NIL"; proof.phase = "sinkAfterObservation"
            }
            do { try check(context, afterCall: true) } catch let stop as PublicWriterStop {
                proof.status = stop.status
                proof.phase = "sinkAfterObservation"
            } catch { proof.status = "INTERNAL_BOUNDARY_FAILURE" }
        }
        if proof.status == "REAL_WRITER_OBSERVED" {
            do { try check(context, afterCall: false) } catch let stop as PublicWriterStop {
                proof.status = stop.status
            } catch { proof.status = "INTERNAL_BOUNDARY_FAILURE" }
        }
        proof.workerCancelledAtFinish = Task<Never, Never>.isCancelled
        proof.finishedWall = Date().timeIntervalSince1970
        proof.finished = context.elapsed
        if proof.status == "REAL_WRITER_OBSERVED" {
            if proof.workerCancelledAtFinish == true { proof.status = "CANCELLED" }
            if !proof.finished.isFinite || proof.finished < 0 || !proof.finishedWall.isFinite {
                proof.status = "INVALID_CLOCK"
            } else if proof.finished >= 5 {
                proof.status = "API_OVERRAN_BUDGET"; proof.phase = "workerFinalization"
            } else if proof.finishedWall < context.wallLower || proof.finishedWall > context.wallUpper {
                proof.status = "CLOCK_INTERVAL_DISCONTINUITY"; proof.phase = "workerFinalization"
            }
        }
        return proof
    }

    private static func perform(_ context: PublicWriterContext, proof: inout PublicWriterProof) {
        guard !proof.workerWasMainThread else { proof.status = "WORKER_ON_MAIN_THREAD"; return }
        guard proof.hostVerified, proof.processID > 0, proof.workerProcessID == proof.processID else {
            proof.status = "WRONG_HOST"; return
        }
        do {
            proof.phase = "sinkBeforeBaseline"
            try check(context, afterCall: false)
            proof.sinkBeforeBaseline = AppLogger.testSink == nil
            proof.sinkBeforeCompleted = context.elapsed
            try check(context, afterCall: true)
            guard proof.sinkBeforeBaseline == true else { proof.status = "SINK_NOT_NIL"; return }
            var baseline = autoreleasepool { read(context, attempt: 0, baseline: true) }
            baseline.returned = context.elapsed
            proof.baseline = baseline
            proof.phase = "baseline." + baseline.phase
            try check(context, afterCall: true)
            guard baseline.status == "EMPTY_COMPLETE", baseline.exhausted == true, baseline.objectsRead == 0 else {
                proof.status = baseline.status; return
            }
            proof.phase = "sinkBeforeEmit"
            try check(context, afterCall: false)
            proof.sinkBeforeEmit = AppLogger.testSink == nil
            proof.sinkBeforeEmitCompleted = context.elapsed
            try check(context, afterCall: true)
            guard proof.sinkBeforeEmit == true else { proof.status = "SINK_NOT_NIL"; return }
            proof.phase = "emit"
            try check(context, afterCall: false)
            proof.emitStarted = context.elapsed
            proof.emitCallCount = 1
            AppLogger.emit(.scheduler, .error, context.input.nonce)
            proof.emitCompleted = context.elapsed
            try check(context, afterCall: true)
            for attempt in 1...21 {
                try check(context, afterCall: false)
                var query = autoreleasepool { read(context, attempt: attempt, baseline: false) }
                query.returned = context.elapsed
                proof.postReads.append(query)
                proof.phase = "postRead." + query.phase
                try check(context, afterCall: true)
                if query.status == "ONE_COMPLETE" { proof.status = "REAL_WRITER_OBSERVED"; return }
                guard query.status == "EMPTY_COMPLETE" else { proof.status = query.status; return }
                guard attempt < 21 else { proof.status = "POST_READ_LIMIT"; return }
                try check(context, afterCall: false)
                let gapStart = context.elapsed
                guard gapStart + 0.25 < 5 else { proof.status = "NOT_OBSERVED_WITHIN_BUDGET"; return }
                Thread.sleep(forTimeInterval: 0.25)
                proof.pollGaps.append([gapStart, context.elapsed])
                try check(context, afterCall: false)
                guard let returned = proof.postReads.last?.returned, context.elapsed - returned >= 0.25 else {
                    proof.status = "POLL_GAP_NOT_MET"; return
                }
            }
        } catch let stop as PublicWriterStop {
            proof.status = stop.status
        } catch {
            proof.status = "INTERNAL_BOUNDARY_FAILURE"
        }
    }

    private static func read(_ context: PublicWriterContext, attempt: Int, baseline: Bool) -> PublicWriterQuery {
        var query = PublicWriterQuery(attempt: attempt)
        do {
            query.phase = "store"
            try check(context, afterCall: false)
            query.started = context.elapsed
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            query.storeCompleted = context.elapsed
            try check(context, afterCall: true)
            query.phase = "position"
            try check(context, afterCall: false)
            let position = store.position(date: Date(timeIntervalSince1970: context.wallLower))
            query.positionCompleted = context.elapsed
            try check(context, afterCall: true)
            query.phase = "getEntries"
            try check(context, afterCall: false)
            let entries = try store.getEntries(with: [], at: position,
                matching: NSPredicate(format: "eventMessage == %@", context.input.nonce))
            query.queryCreated = context.elapsed
            try check(context, afterCall: true)
            query.phase = "makeIterator"
            try check(context, afterCall: false)
            var iterator = entries.makeIterator()
            query.iteratorCreated = context.elapsed
            query.objectsRead = 0
            query.exhausted = false
            try check(context, afterCall: true)
            for _ in 0..<32 {
                query.phase = "iterator.next"
                try check(context, afterCall: false)
                let entry = iterator.next()
                query.lastNextCompleted = context.elapsed
                if entry == nil {
                    query.exhausted = true
                } else {
                    query.objectsRead = (query.objectsRead ?? 0) + 1
                }
                try check(context, afterCall: true)
                guard let entry else {
                    query.status = query.objectsRead == 0 ? "EMPTY_COMPLETE" : "ONE_COMPLETE"
                    return finish(query, context: context)
                }
                guard let log = entry as? OSLogEntryLog else {
                    query.typedLog = false; query.status = "INTEGRITY_NON_LOG"; return finish(query, context: context)
                }
                query.typedLog = true
                query.phase = "entry.composedMessage"
                try check(context, afterCall: false)
                let message = log.composedMessage
                try check(context, afterCall: true)
                query.observedMessageSHA256 = digest(message)
                guard message == context.input.nonce else {
                    query.status = "INTEGRITY_UNRELATED_MESSAGE"; return finish(query, context: context)
                }
                if baseline { query.status = "BASELINE_PRESENT"; return finish(query, context: context) }
                let row = try capture(log, message: message, context: context, query: &query)
                query.entry = row
                guard matches(row, context: context) else {
                    query.status = "TUPLE_MISMATCH"; return finish(query, context: context)
                }
                guard query.objectsRead == 1 else {
                    query.status = "DUPLICATE_OWNED_ROWS"; return finish(query, context: context)
                }
            }
            query.status = "READBACK_TRUNCATED"
        } catch let stop as PublicWriterStop {
            query.status = stop.status
        } catch {
            let actual = error as NSError
            let domain = actual.domain
            query.status = query.phase == "store" ? "STORE_UNAVAILABLE" : "QUERY_UNAVAILABLE"
            query.errorCode = actual.code
            query.errorDomainSHA256 = digest(domain)
            if domain.count <= 96 && !domain.contains(context.input.nonce)
                && domain.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil {
                query.errorDomain = domain
            }
        }
        return finish(query, context: context)
    }

    private static func capture(_ log: OSLogEntryLog, message: String, context: PublicWriterContext,
                                query: inout PublicWriterQuery) throws -> PublicWriterEntry {
        query.phase = "entry.processIdentifier"
        try check(context, afterCall: false)
        let processID = Int(log.processIdentifier)
        try check(context, afterCall: true)
        query.phase = "entry.subsystem"
        try check(context, afterCall: false)
        let subsystem = log.subsystem
        try check(context, afterCall: true)
        query.phase = "entry.category"
        try check(context, afterCall: false)
        let category = log.category
        try check(context, afterCall: true)
        query.phase = "entry.level"
        try check(context, afterCall: false)
        let level = log.level
        try check(context, afterCall: true)
        query.phase = "entry.date"
        try check(context, afterCall: false)
        let date = log.date.timeIntervalSince1970
        try check(context, afterCall: true)
        return PublicWriterEntry(messageEqual: message == context.input.nonce, messageSHA256: digest(message),
            processID: processID, subsystemSHA256: digest(subsystem), categorySHA256: digest(category),
            knownSubsystem: subsystem == context.subsystem ? subsystem : nil,
            knownCategory: category == "Scheduler" ? "Scheduler" : nil,
            levelRaw: level.rawValue, isError: level == .error, date: date)
    }

    private static func matches(_ row: PublicWriterEntry, context: PublicWriterContext) -> Bool {
        row.messageEqual && row.messageSHA256 == context.nonceSHA256 && row.processID == context.input.processID
            && row.subsystemSHA256 == digest(context.subsystem) && row.categorySHA256 == digest("Scheduler")
            && row.isError && row.levelRaw == OSLogEntryLog.Level.error.rawValue
            && row.date.isFinite && row.date >= context.wallLower && row.date <= context.wallUpper
    }

    private static func finish(_ value: PublicWriterQuery, context: PublicWriterContext) -> PublicWriterQuery {
        var value = value
        value.completed = context.elapsed
        do { try check(context, afterCall: true) } catch let stop as PublicWriterStop {
            value.status = stop.status
        } catch { value.status = "INTERNAL_BOUNDARY_FAILURE" }
        return value
    }

    private static func check(_ context: PublicWriterContext, afterCall: Bool) throws {
        if context.input.cancelledAtStart || Task<Never, Never>.isCancelled {
            throw PublicWriterStop(status: "CANCELLED")
        }
        let elapsed = context.elapsed
        let wall = Date().timeIntervalSince1970
        guard context.monotonicStart.isFinite, context.wallLower.isFinite, context.wallUpper.isFinite,
              elapsed.isFinite, elapsed >= 0, wall.isFinite else { throw PublicWriterStop(status: "INVALID_CLOCK") }
        guard elapsed < 5 else {
            throw PublicWriterStop(status: afterCall ? "API_OVERRAN_BUDGET" : "NOT_OBSERVED_WITHIN_BUDGET")
        }
        guard wall >= context.wallLower && wall <= context.wallUpper else {
            throw PublicWriterStop(status: "CLOCK_INTERVAL_DISCONTINUITY")
        }
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func nullable(_ value: Any?) -> Any { value ?? NSNull() }

    static func time(_ value: Double?) -> Any {
        guard let value else { return NSNull() }
        return String(describing: value)
    }
}
