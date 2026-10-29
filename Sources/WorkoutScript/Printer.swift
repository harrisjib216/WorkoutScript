extension Workout {
    /// The workout written out as a script in the standard layout. Compiling the result gives back an equal workout.
    public var script: String {
        var header = activity.rawValue
        if let location { header += " \(location.rawValue)" }
        if let name { header += " \(quoted(name))" }

        var sections = [header]
        if let warmup { sections.append(line("warmup", warmup)) }
        var singles: [String] = []
        for block in blocks {
            // One-step, one-time blocks are plain lines; consecutive ones stay together.
            if block.iterations == 1, block.intervals.count == 1 {
                singles.append(line(block.intervals[0]))
                continue
            }
            if !singles.isEmpty {
                sections.append(singles.joined(separator: "\n"))
                singles = []
            }
            if block.intervals.count == 1 {
                sections.append("\(block.iterations)x \(line(block.intervals[0]))")
            } else {
                let body = block.intervals.map { "  " + line($0) }.joined(separator: "\n")
                sections.append("\(block.iterations)x {\n\(body)\n}")
            }
        }
        if !singles.isEmpty { sections.append(singles.joined(separator: "\n")) }
        if let cooldown { sections.append(line("cooldown", cooldown)) }
        return sections.joined(separator: "\n\n") + "\n"
    }

    private func line(_ interval: Interval) -> String {
        switch interval.purpose {
        case .work: step(interval.step, afterKeyword: false)
        case .recovery: line("recover", interval.step)
        }
    }

    private func line(_ keyword: String, _ step: Step) -> String {
        let rest = self.step(step, afterKeyword: true)
        return rest.isEmpty ? keyword : "\(keyword) \(rest)"
    }

    /// After a keyword an open goal goes unsaid: `recover` rather than `recover open`.
    private func step(_ step: Step, afterKeyword: Bool) -> String {
        var parts: [String] = []
        if step.goal != .open || (!afterKeyword && step.alert == nil && step.label == nil) {
            parts.append(step.goal.scriptText)
        }
        if let alert = step.alert { parts.append("@ \(alert.scriptText)") }
        if let label = step.label { parts.append(quoted(label)) }
        return parts.joined(separator: " ")
    }

    private func quoted(_ text: String) -> String {
        "\"" + String(text.map { $0 == "\"" ? "'" : $0 }) + "\""
    }
}

extension Goal {
    /// The goal as script text: `15min`, `800m`, `100m in 1:45`, `open`.
    public var scriptText: String {
        switch self {
        case .open: "open"
        case .time(let value, let unit): format(value) + unit.rawValue
        case .distance(let value, let unit): format(value) + unit.rawValue
        case .energy(let value, let unit): format(value) + unit.rawValue
        case .poolSwim(let value, let unit, let seconds): "\(format(value))\(unit.rawValue) in \(clock(seconds))"
        }
    }
}

extension Alert {
    /// The target as script text: `3:50-4:00/km`, `avg 250W`, `zone 2`.
    public var scriptText: String {
        switch self {
        case .pace(let target, let unit, let metric):
            average(metric) + text(target, clock) + unit.rawValue
        case .speed(let target, let unit, let metric):
            average(metric) + text(target, format) + unit.rawValue
        case .heartRate(let beats):
            text(.range(beats), format) + "bpm"
        case .heartRateZone(let zone):
            "zone \(zone)"
        case .power(let target, let metric):
            average(metric) + text(target, format) + "W"
        case .powerZone(let zone):
            "power zone \(zone)"
        case .cadence(let target, let unit):
            text(target, format) + unit.rawValue
        }
    }

    private func average(_ metric: Metric) -> String {
        metric == .average ? "avg " : ""
    }

    private func text(_ target: Target, _ format: (Double) -> String) -> String {
        switch target {
        case .value(let value): format(value)
        case .range(let range): "\(format(range.lowerBound))-\(format(range.upperBound))"
        }
    }
}

/// `800`, `1.5`, `0.25`: no trailing zeros, at most three decimals.
func format(_ value: Double) -> String {
    let rounded = (value * 1000).rounded() / 1000
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    var text = String(rounded)
    while text.hasSuffix("0") { text.removeLast() }
    return text
}

/// `3:50`, `1:02:30`. Fractions of a second are kept, so `3:50.5` survives a round trip.
func clock(_ seconds: Double) -> String {
    let whole = Int(seconds)
    let fraction = seconds - Double(whole)
    let hours = whole / 3600
    let minutes = whole / 60 % 60
    let secondsText = (whole % 60 < 10 ? "0" : "") + format(Double(whole % 60) + fraction)
    if hours > 0 {
        return "\(hours):" + (minutes < 10 ? "0" : "") + "\(minutes):\(secondsText)"
    }
    return "\(minutes):\(secondsText)"
}
