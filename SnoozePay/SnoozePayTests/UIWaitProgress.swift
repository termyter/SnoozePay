import Foundation

/// Independent delivery evidence; a default-mode Timer alone cannot diagnose a main-queue stall.
@MainActor
final class UIWaitProgress {
    private enum Source: String, CaseIterable {
        case defaultTimer, commonTimer, gcd, mainActor
    }

    private let interval: TimeInterval
    private let started: Date
    private let deadline: Date
    private let startContext: String
    private var censuses: [Source: RunLoopCensus]
    private var contexts: [Source: Set<String>] = [:]
    private var defaultTimer: Timer?
    private var commonTimer: Timer?
    private var dispatchTimer: DispatchSourceTimer?
    private var actorTask: Task<Void, Never>?
    private var active = false
    private var observationStoppedAt: Date?

    init(interval: TimeInterval, timeout: TimeInterval, started: Date = Date()) {
        self.interval = interval
        self.started = started
        self.deadline = started.addingTimeInterval(timeout)
        self.startContext = Self.context()
        self.censuses = Dictionary(uniqueKeysWithValues: Source.allCases.map {
            ($0, RunLoopCensus(interval: interval, started: started))
        })
    }

    func start(poll: @escaping () -> Void) {
        active = true
        let defaultTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.record(.defaultTimer) }
        }
        self.defaultTimer = defaultTimer
        RunLoop.main.add(defaultTimer, forMode: .default)
        // Observe readiness in common modes; the default-mode source is diagnostic only.
        let commonTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.record(.commonTimer) == true else { return }
                poll()
            }
        }
        self.commonTimer = commonTimer
        RunLoop.main.add(commonTimer, forMode: .common)
        let dispatchTimer = DispatchSource.makeTimerSource(queue: .main)
        dispatchTimer.schedule(deadline: .now() + interval, repeating: interval)
        dispatchTimer.setEventHandler { [weak self] in
            _ = MainActor.assumeIsolated { self?.record(.gcd) }
        }
        self.dispatchTimer = dispatchTimer
        dispatchTimer.resume()
        actorTask = Task { @MainActor [weak self, interval] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) } catch { return }
                guard !Task.isCancelled, let self, self.record(.mainActor) else { return }
            }
        }
    }

    func cancel(at moment: Date = Date()) {
        observationStoppedAt = observationStoppedAt ?? min(moment, deadline)
        active = false
        defaultTimer?.invalidate()
        defaultTimer = nil
        commonTimer?.invalidate()
        commonTimer = nil
        dispatchTimer?.cancel()
        dispatchTimer = nil
        actorTask?.cancel()
        actorTask = nil
    }

    @discardableResult
    private func record(_ source: Source) -> Bool {
        guard active else { return false }
        let now = Date()
        guard now < deadline else {
            cancel()
            return false
        }
        censuses[source]?.record(at: now)
        contexts[source, default: []].insert(Self.context())
        return true
    }

    func summary(at finished: Date) -> String {
        let sampledUntil = min(finished, observationStoppedAt ?? deadline)
        let unobserved = max(0, finished.timeIntervalSince(sampledUntil))
        let sources = Source.allCases.map { source in
            let census = censuses[source]!
            let gap = census.longestStall(now: sampledUntil)
            let modes = contexts[source, default: []].sorted().joined(separator: ", ")
            return "\(source.rawValue): \(census.ticks.count)/~\(census.expectedTicks(now: sampledUntil)) ticks, "
                + "longest delivery gap \(String(format: "%.2f", gap.to - gap.from))s, contexts=[\(modes)]"
        }.joined(separator: "; ")
        return "Wait started at \(started.timeIntervalSince1970) (\(startContext)); \(sources). "
            + "Sampling ended at \(sampledUntil.timeIntervalSince1970); waiter returned "
            + "\(String(format: "%.2f", unobserved))s after sampling ended (unobserved). "
            + "Default Timer silence alone may be mode suppression. GCD/MainActor ticks prove some queue/actor "
            + "progress; silence across all sources still does not identify the blocking code."
    }

    private static func context() -> String {
        "mainThread=\(Thread.isMainThread), mode=\(RunLoop.current.currentMode?.rawValue ?? "nil")"
    }
}

/// MainActor-owned route milestones, with a separately locked background clock.
/// One capped report per fixture includes events on either side of its unchanged deadline.
@MainActor
final class UIWaitTimeline {
    let fixtureID = UUID()
    private var events: [(name: String, time: Date)] = []
    private var lastStates: [String: String] = [:]
    private var omitted = 0
    private var heartbeat: BackgroundWaitHeartbeat?

    func record(_ event: String, at time: Date = Date()) {
        guard events.count < 96 else { omitted += 1; return }
        events.append((event, time))
    }

    func recordState(_ event: String, state: String) {
        guard lastStates[event] != state else { return }
        lastStates[event] = state
        record(event + " " + state)
    }

    func beginWait(started: Date, timeout: TimeInterval) {
        heartbeat?.cancel()
        let heartbeat = BackgroundWaitHeartbeat(started: started, timeout: timeout)
        self.heartbeat = heartbeat
        record("wait.began", at: started)
        heartbeat.start(interval: 0.05)
    }

    func finish() -> String {
        heartbeat?.cancel()
        let ticks = heartbeat?.snapshot().ticks ?? []
        let deadline = heartbeat?.deadline
        let lines = events.map { event in
            let phase = deadline.map { event.time <= $0 ? "before/on deadline" : "after deadline" } ?? "no wait"
            return "\(event.time.timeIntervalSince1970) [\(phase)] \(event.name)"
        }.joined(separator: "\n")
        let before = ticks.filter { tick in deadline.map { tick <= $0 } ?? false }.count
        let tickTimes = ticks.map { $0.timeIntervalSince1970 }
        var census = RunLoopCensus(interval: 0.05, started: heartbeat?.started ?? Date())
        ticks.forEach { census.record(at: $0) }
        let gap = census.longestStall(now: min(Date(), heartbeat?.end ?? Date()))
        return """
            UITour fixture=\(fixtureID.uuidString) timeline (omitted=\(omitted), \
            nominalDeadline=\(deadline?.timeIntervalSince1970.description ?? "none")):
            \(lines)
            Background heartbeat: before/on=\(before), after=\(ticks.count - before), \
            first=\(tickTimes.first?.description ?? "none"), last=\(tickTimes.last?.description ?? "none"), \
            hardEnd=\(heartbeat?.end.timeIntervalSince1970.description ?? "none"), \
            longestGap=\(gap.to - gap.from)s (+\(gap.from) to +\(gap.to)). \
            Counts distinguish delivery sources, not a blocking stack or owner.
            """
    }
}
