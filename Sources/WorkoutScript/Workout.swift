/// A structured workout: an activity, an optional warmup, blocks of repeated intervals, and an optional cooldown.
///
/// It mirrors WorkoutKit's `CustomWorkout` one to one, but it is plain Swift, so the language builds and tests on
/// Linux too. `WorkoutScriptKit` converts it to and from WorkoutKit.
public struct Workout: Hashable, Sendable {
    public var activity: Activity
    public var location: Location?
    public var name: String?
    public var warmup: Step?
    public var blocks: [Block]
    public var cooldown: Step?

    public init(
        activity: Activity, location: Location? = nil, name: String? = nil,
        warmup: Step? = nil, blocks: [Block] = [], cooldown: Step? = nil
    ) {
        self.activity = activity
        self.location = location
        self.name = name
        self.warmup = warmup
        self.blocks = blocks
        self.cooldown = cooldown
    }
}

/// The activities a script can start with. Each one maps to an `HKWorkoutActivityType` that supports custom workouts.
public enum Activity: String, CaseIterable, Sendable {
    case running, cycling, walking, hiking, swimming, rowing, elliptical, stairs, hiit
}

public enum Location: String, CaseIterable, Sendable {
    case indoor, outdoor
}

/// Intervals that run in order, `iterations` times. WorkoutKit's `IntervalBlock`.
public struct Block: Hashable, Sendable {
    public var iterations: Int
    public var intervals: [Interval]

    public init(iterations: Int = 1, intervals: [Interval]) {
        self.iterations = iterations
        self.intervals = intervals
    }
}

/// A work or recovery step inside a block. WorkoutKit's `IntervalStep`.
public struct Interval: Hashable, Sendable {
    public enum Purpose: Sendable {
        case work, recovery
    }

    public var purpose: Purpose
    public var step: Step

    public init(_ purpose: Purpose, _ step: Step) {
        self.purpose = purpose
        self.step = step
    }
}

/// What to do, what to aim for while doing it, and the name the watch shows. WorkoutKit's `WorkoutStep`.
public struct Step: Hashable, Sendable {
    public var goal: Goal
    public var alert: Alert?
    public var label: String?

    public init(goal: Goal = .open, alert: Alert? = nil, label: String? = nil) {
        self.goal = goal
        self.alert = alert
        self.label = label
    }
}

/// When a step ends. Units stay as written, so `1km` prints back as `1km` and not `1000m`.
public enum Goal: Hashable, Sendable {
    /// The step lasts until you move on by hand.
    case open
    case time(Double, TimeUnit)
    case distance(Double, DistanceUnit)
    case energy(Double, EnergyUnit)
    /// A pool swim distance with a time to swim it in: `100m in 1:45`.
    case poolSwim(Double, DistanceUnit, seconds: Double)
}

public enum TimeUnit: String, CaseIterable, Sendable {
    case seconds = "s", minutes = "min", hours = "h"

    public var seconds: Double {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3600
        }
    }
}

public enum DistanceUnit: String, CaseIterable, Sendable {
    case meters = "m", kilometers = "km", miles = "mi", yards = "yd"

    public var meters: Double {
        switch self {
        case .meters: 1
        case .kilometers: 1000
        case .miles: 1609.344
        case .yards: 0.9144
        }
    }
}

public enum EnergyUnit: String, CaseIterable, Sendable {
    case kilocalories = "kcal", kilojoules = "kJ"
}

/// A single value or a range to stay inside.
public enum Target: Hashable, Sendable {
    case value(Double)
    case range(ClosedRange<Double>)

    public var lowerBound: Double {
        switch self {
        case .value(let value): value
        case .range(let range): range.lowerBound
        }
    }

    public var upperBound: Double {
        switch self {
        case .value(let value): value
        case .range(let range): range.upperBound
        }
    }

    /// The value, or the middle of the range.
    public var middle: Double { (lowerBound + upperBound) / 2 }
}

/// Whether an alert watches the current reading or the average over the step. WorkoutKit's `WorkoutAlertMetric`.
public enum Metric: Sendable {
    case current, average
}

/// What the watch keeps you on during a step, and taps your wrist about when you drift off it.
public enum Alert: Hashable, Sendable {
    /// Seconds per kilometer or per mile, so a lower number is faster.
    case pace(Target, PaceUnit, Metric)
    case speed(Target, SpeedUnit, Metric)
    /// Beats per minute. WorkoutKit has range and zone alerts for heart rate, but no single-value alert.
    case heartRate(ClosedRange<Double>)
    case heartRateZone(Int)
    /// Watts.
    case power(Target, Metric)
    case powerZone(Int)
    /// Steps or pedal revolutions per minute.
    case cadence(Target, CadenceUnit)
}

public enum PaceUnit: String, CaseIterable, Sendable {
    case perKilometer = "/km", perMile = "/mi"

    public var meters: Double {
        switch self {
        case .perKilometer: 1000
        case .perMile: 1609.344
        }
    }
}

public enum SpeedUnit: String, CaseIterable, Sendable {
    case kilometersPerHour = "km/h", milesPerHour = "mph", metersPerSecond = "m/s"

    public var metersPerSecond: Double {
        switch self {
        case .kilometersPerHour: 1000.0 / 3600
        case .milesPerHour: 1609.344 / 3600
        case .metersPerSecond: 1
        }
    }
}

public enum CadenceUnit: String, CaseIterable, Sendable {
    case stepsPerMinute = "spm", revolutionsPerMinute = "rpm"
}

extension Alert {
    /// A pace or speed target in meters per second, the unit WorkoutKit's speed alerts take.
    /// A pace range flips: the slow end of the pace is the low end of the speed.
    public var metersPerSecond: Target? {
        switch self {
        case .pace(.value(let seconds), let unit, _):
            .value(unit.meters / seconds)
        case .pace(.range(let seconds), let unit, _):
            .range(unit.meters / seconds.upperBound...unit.meters / seconds.lowerBound)
        case .speed(.value(let speed), let unit, _):
            .value(speed * unit.metersPerSecond)
        case .speed(.range(let speed), let unit, _):
            .range(speed.lowerBound * unit.metersPerSecond...speed.upperBound * unit.metersPerSecond)
        default:
            nil
        }
    }
}
