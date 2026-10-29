/// What the device that runs the workout supports. `WorkoutScriptKit` answers with WorkoutKit's own checks,
/// so the compiler reports an unsupported goal or alert at the exact text that asked for it.
public protocol WorkoutPlatform: Sendable {
    func supports(_ activity: Activity, location: Location?) -> Bool
    func supports(_ goal: Goal, for activity: Activity, location: Location?) -> Bool
    func supports(_ alert: Alert, for activity: Activity, location: Location?) -> Bool
}

/// The result of compiling a script.
public struct Compilation: Sendable {
    public var file: SourceFile
    /// The workout, or nil when the script has errors.
    public var workout: Workout?
    /// Errors, warnings and notes, in the order they appear in the script.
    public var diagnostics: [Diagnostic]
    public var sourceMap: SourceMap

    public var errors: [Diagnostic] { diagnostics.filter { $0.severity == .error } }
}

public enum Compiler {
    /// Compiles a script. Pass a platform to also check every goal and alert against what it supports.
    public static func compile(
        _ text: String, name: String = "<input>", platform: (any WorkoutPlatform)? = nil
    ) -> Compilation {
        var lexer = Lexer(text)
        let tokens = lexer.tokenize()
        var parser = Parser(text: text, tokens: tokens, diagnostics: lexer.diagnostics)
        let workout = parser.parseWorkout()
        var diagnostics = parser.diagnostics
        if let workout, let platform, !diagnostics.contains(where: { $0.severity == .error }) {
            diagnostics += check(workout, sourceMap: parser.sourceMap, against: platform)
        }
        diagnostics = diagnostics.enumerated()
            .sorted { ($0.element.range.lowerBound, $0.offset) < ($1.element.range.lowerBound, $1.offset) }
            .map(\.element)
        let failed = diagnostics.contains { $0.severity == .error }
        return Compilation(
            file: SourceFile(name: name, text: text), workout: failed ? nil : workout,
            diagnostics: diagnostics, sourceMap: parser.sourceMap)
    }

    static func check(_ workout: Workout, sourceMap: SourceMap, against platform: any WorkoutPlatform) -> [Diagnostic] {
        let header = sourceMap.header ?? SourceRange(0, 0)
        let activity = workout.activity
        let location = workout.location
        guard platform.supports(activity, location: location) else {
            return [Diagnostic(.error, "WorkoutKit can't run custom \(activity.rawValue) workouts", at: header)]
        }

        let place = [location?.rawValue, activity.rawValue].compactMap { $0 }.joined(separator: " ")
        var diagnostics: [Diagnostic] = []
        for (path, step) in workout.steps {
            let spans = sourceMap.steps[path]
            if !platform.supports(step.goal, for: activity, location: location) {
                diagnostics.append(Diagnostic(
                    .error, "WorkoutKit doesn't support \(step.goal.kindName) goals for \(place)",
                    at: spans?.goal ?? spans?.step ?? header))
            }
            if let alert = step.alert, !platform.supports(alert, for: activity, location: location) {
                diagnostics.append(Diagnostic(
                    .error, "WorkoutKit doesn't support \(alert.kindName) alerts for \(place)",
                    at: spans?.alert ?? spans?.step ?? header))
            }
        }
        return diagnostics
    }
}

extension Workout {
    /// Every step with its position, in the order the watch runs them, each repeat listed once.
    public var steps: [(path: StepPath, step: Step)] {
        var steps: [(StepPath, Step)] = []
        if let warmup { steps.append((.warmup, warmup)) }
        for (blockIndex, block) in blocks.enumerated() {
            for (index, interval) in block.intervals.enumerated() {
                steps.append((.interval(block: blockIndex, index: index), interval.step))
            }
        }
        if let cooldown { steps.append((.cooldown, cooldown)) }
        return steps
    }
}

extension Goal {
    public var kindName: String {
        switch self {
        case .open: "open"
        case .time: "time"
        case .distance: "distance"
        case .energy: "energy"
        case .poolSwim: "pool swim"
        }
    }
}

extension Alert {
    public var kindName: String {
        switch self {
        case .pace(_, _, .average): "average pace"
        case .pace: "pace"
        case .speed(_, _, .average): "average speed"
        case .speed: "speed"
        case .heartRate: "heart rate"
        case .heartRateZone: "heart rate zone"
        case .power(_, .average): "average power"
        case .power: "power"
        case .powerZone: "power zone"
        case .cadence: "cadence"
        }
    }
}
