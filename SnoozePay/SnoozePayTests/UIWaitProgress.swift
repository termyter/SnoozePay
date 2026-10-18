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

    init(interval: TimeInterval, timeout: TimeInterval) {
        let started = Date()
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

    func cancel() {
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
        let sources = Source.allCases.map { source in
            let census = censuses[source]!
            let gap = census.longestStall(now: finished)
            let modes = contexts[source, default: []].sorted().joined(separator: ", ")
            return "\(source.rawValue): \(census.ticks.count)/~\(census.expectedTicks(now: finished)) ticks, "
                + "longest delivery gap \(String(format: "%.2f", gap.to - gap.from))s, contexts=[\(modes)]"
        }.joined(separator: "; ")
        return "Wait started at \(started.timeIntervalSince1970) (\(startContext)); \(sources). "
            + "Default Timer silence alone may be mode suppression. GCD/MainActor ticks prove some queue/actor "
            + "progress; silence across all sources still does not identify the blocking code."
    }

    private static func context() -> String {
        "mainThread=\(Thread.isMainThread), mode=\(RunLoop.current.currentMode?.rawValue ?? "nil")"
    }
}
