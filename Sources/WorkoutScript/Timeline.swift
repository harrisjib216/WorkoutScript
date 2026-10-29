/// One step as the watch will run it, with repeats expanded.
public struct TimelineEntry: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable {
        case warmup, work, recovery, cooldown
    }

    /// The entry's position in the timeline.
    public var id: Int
    public var kind: Kind
    public var step: Step
    public var path: StepPath
    /// Which pass through the block this is, starting at 1. Nil outside blocks.
    public var iteration: Int?
    public var estimatedSeconds: Double?
}

extension Workout {
    /// Every step in the order the watch runs them, with each block repeated as many times as it runs.
    public var timeline: [TimelineEntry] {
        var entries: [TimelineEntry] = []
        func add(_ kind: TimelineEntry.Kind, _ step: Step, _ path: StepPath, _ iteration: Int?) {
            entries.append(TimelineEntry(
                id: entries.count, kind: kind, step: step, path: path, iteration: iteration,
                estimatedSeconds: step.estimatedSeconds))
        }
        if let warmup { add(.warmup, warmup, .warmup, nil) }
        for (blockIndex, block) in blocks.enumerated() {
            for iteration in 1...max(block.iterations, 1) {
                for (index, interval) in block.intervals.enumerated() {
                    let kind: TimelineEntry.Kind = interval.purpose == .work ? .work : .recovery
                    add(kind, interval.step, .interval(block: blockIndex, index: index),
                        block.iterations > 1 ? iteration : nil)
                }
            }
        }
        if let cooldown { add(.cooldown, cooldown, .cooldown, nil) }
        return entries
    }

    /// The total of every step's estimate, and how many steps have no estimate (open goals, or distances with no
    /// pace or speed target to work from).
    public var estimatedDuration: (seconds: Double, unknownSteps: Int) {
        timeline.reduce((0, 0)) { total, entry in
            guard let seconds = entry.estimatedSeconds else { return (total.0, total.1 + 1) }
            return (total.0 + seconds, total.1)
        }
    }

    /// The total distance of every distance goal, in meters.
    public var totalMeters: Double {
        timeline.reduce(0) { total, entry in
            switch entry.step.goal {
            case .distance(let value, let unit), .poolSwim(let value, let unit, _): total + value * unit.meters
            default: total
            }
        }
    }
}

extension Step {
    /// How long the step should take: a time goal as written, or a distance at the middle of its pace or speed
    /// target. Nil when there is nothing to estimate from.
    public var estimatedSeconds: Double? {
        switch goal {
        case .time(let value, let unit):
            return value * unit.seconds
        case .poolSwim(_, _, let seconds):
            return seconds
        case .distance(let value, let unit):
            guard let speed = alert?.metersPerSecond else { return nil }
            return value * unit.meters / speed.middle
        case .open, .energy:
            return nil
        }
    }
}
