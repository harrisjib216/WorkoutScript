#if canImport(WorkoutKit)
import Foundation
import HealthKit
import WorkoutKit
import WorkoutScript

extension Workout {
    /// The workout as WorkoutKit's custom workout.
    public var customWorkout: CustomWorkout {
        CustomWorkout(
            activity: activity.workoutActivityType,
            location: location?.sessionLocationType ?? .unknown,
            displayName: name,
            warmup: warmup?.workoutStep,
            blocks: blocks.map { block in
                IntervalBlock(
                    steps: block.intervals.map { IntervalStep($0.purpose.intervalPurpose, step: $0.step.workoutStep) },
                    iterations: block.iterations)
            },
            cooldown: cooldown?.workoutStep)
    }

    /// A plan to preview with `.workoutPreview`, schedule with `WorkoutScheduler`, or save as a `.workout` file.
    public func workoutPlan(id: UUID = UUID()) -> WorkoutPlan {
        WorkoutPlan(.custom(customWorkout), id: id)
    }

    /// Reads a custom workout back, so a `.workout` file can be shown as a script.
    ///
    /// WorkoutKit stores pace as speed, so speed alerts come back as pace for running, walking and hiking, and as
    /// km/h for everything else. Cadence comes back as rpm for cycling and spm otherwise.
    public init(_ workout: CustomWorkout) throws(UnsupportedWorkout) {
        guard let activity = Activity(workout.activity) else { throw .activity(workout.activity.rawValue) }
        let location: Location? = switch workout.location {
        case .indoor: .indoor
        case .outdoor: .outdoor
        default: nil
        }
        func step(_ step: WorkoutStep) throws(UnsupportedWorkout) -> Step {
            try Step(step, activity: activity)
        }
        self.init(
            activity: activity, location: location, name: workout.displayName,
            warmup: try workout.warmup.map(step),
            blocks: try workout.blocks.map { block throws(UnsupportedWorkout) in
                Block(iterations: block.iterations, intervals: try block.steps.map { interval throws(UnsupportedWorkout) in
                    Interval(interval.purpose == .work ? .work : .recovery, try step(interval.step))
                })
            },
            cooldown: try workout.cooldown.map(step))
    }
}

/// Something in a WorkoutKit workout that a script can't express.
public enum UnsupportedWorkout: Error, Equatable {
    case activity(UInt)
    case goal(String)
    case alert(String)
}

/// Answers the compiler's support questions with WorkoutKit's own `CustomWorkout.supports…` checks.
public struct WorkoutKitPlatform: WorkoutPlatform {
    public init() {}

    public func supports(_ activity: Activity, location: Location?) -> Bool {
        CustomWorkout.supportsActivity(activity.workoutActivityType)
    }

    public func supports(_ goal: Goal, for activity: Activity, location: Location?) -> Bool {
        CustomWorkout.supportsGoal(
            goal.workoutGoal, activity: activity.workoutActivityType,
            location: location?.sessionLocationType ?? .unknown)
    }

    public func supports(_ alert: Alert, for activity: Activity, location: Location?) -> Bool {
        CustomWorkout.supportsAlert(
            alert.workoutAlert, activity: activity.workoutActivityType,
            location: location?.sessionLocationType ?? .unknown)
    }
}

extension WorkoutPlatform where Self == WorkoutKitPlatform {
    public static var workoutKit: WorkoutKitPlatform { WorkoutKitPlatform() }
}

// MARK: - Script to WorkoutKit

extension Activity {
    public var workoutActivityType: HKWorkoutActivityType {
        switch self {
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .hiking: .hiking
        case .swimming: .swimming
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .stairs: .stairClimbing
        case .hiit: .highIntensityIntervalTraining
        }
    }

    init?(_ type: HKWorkoutActivityType) {
        guard let match = Activity.allCases.first(where: { $0.workoutActivityType == type }) else { return nil }
        self = match
    }
}

extension Location {
    var sessionLocationType: HKWorkoutSessionLocationType {
        switch self {
        case .indoor: .indoor
        case .outdoor: .outdoor
        }
    }
}

extension Interval.Purpose {
    var intervalPurpose: IntervalStep.Purpose {
        switch self {
        case .work: .work
        case .recovery: .recovery
        }
    }
}

extension Step {
    var workoutStep: WorkoutStep {
        WorkoutStep(goal: goal.workoutGoal, alert: alert?.workoutAlert, displayName: label)
    }
}

extension Goal {
    var workoutGoal: WorkoutGoal {
        switch self {
        case .open:
            .open
        case .time(let value, let unit):
            .time(value, unit.unitDuration)
        case .distance(let value, let unit):
            .distance(value, unit.unitLength)
        case .energy(let value, let unit):
            .energy(value, unit == .kilocalories ? .kilocalories : .kilojoules)
        case .poolSwim(let value, let unit, let seconds):
            .poolSwimDistanceWithTime(
                Measurement(value: value, unit: unit.unitLength), Measurement(value: seconds, unit: .seconds))
        }
    }
}

extension Alert {
    var workoutAlert: any WorkoutAlert {
        switch self {
        case .pace(_, _, let metric), .speed(_, _, let metric):
            // WorkoutKit has no pace unit, so pace goes in as meters per second.
            switch metersPerSecond! {
            case .value(let speed):
                SpeedThresholdAlert.speed(speed, unit: .metersPerSecond, metric: metric.alertMetric)
            case .range(let speed):
                SpeedRangeAlert.speed(speed, unit: .metersPerSecond, metric: metric.alertMetric)
            }
        case .heartRate(let beats):
            HeartRateRangeAlert.heartRate(beats)
        case .heartRateZone(let zone):
            HeartRateZoneAlert.heartRate(zone: zone)
        case .power(.value(let watts), let metric):
            PowerThresholdAlert.power(watts, unit: .watts, metric: metric.alertMetric)
        case .power(.range(let watts), let metric):
            PowerRangeAlert.power(watts, unit: .watts, metric: metric.alertMetric)
        case .powerZone(let zone):
            PowerZoneAlert.power(zone: zone)
        case .cadence(.value(let count), _):
            CadenceThresholdAlert.cadence(count)
        case .cadence(.range(let count), _):
            CadenceRangeAlert.cadence(count)
        }
    }
}

extension Metric {
    var alertMetric: WorkoutAlertMetric {
        switch self {
        case .current: .current
        case .average: .average
        }
    }
}

extension TimeUnit {
    var unitDuration: UnitDuration {
        switch self {
        case .seconds: .seconds
        case .minutes: .minutes
        case .hours: .hours
        }
    }
}

extension DistanceUnit {
    var unitLength: UnitLength {
        switch self {
        case .meters: .meters
        case .kilometers: .kilometers
        case .miles: .miles
        case .yards: .yards
        }
    }
}

// MARK: - WorkoutKit to script

extension Step {
    init(_ step: WorkoutStep, activity: Activity) throws(UnsupportedWorkout) {
        self.init(
            goal: try Goal(step.goal),
            alert: try step.alert.map { alert throws(UnsupportedWorkout) in try Alert(alert, activity: activity) },
            label: step.displayName)
    }
}

extension Goal {
    init(_ goal: WorkoutGoal) throws(UnsupportedWorkout) {
        switch goal {
        case .open:
            self = .open
        case .time(let value, let unit):
            let match = TimeUnit.allCases.first { $0.unitDuration == unit }
            self = match.map { .time(value, $0) }
                ?? .time(Measurement(value: value, unit: unit).converted(to: .seconds).value, .seconds)
        case .distance(let value, let unit):
            let (value, unit) = Self.distance(value, unit)
            self = .distance(value, unit)
        case .energy(let value, let unit):
            self = unit == .kilojoules
                ? .energy(value, .kilojoules)
                : .energy(Measurement(value: value, unit: unit).converted(to: .kilocalories).value, .kilocalories)
        case .poolSwimDistanceWithTime(let distance, let time):
            let (value, unit) = Self.distance(distance.value, distance.unit)
            self = .poolSwim(value, unit, seconds: time.converted(to: .seconds).value)
        @unknown default:
            throw .goal(String(describing: goal))
        }
    }

    private static func distance(_ value: Double, _ unit: UnitLength) -> (Double, DistanceUnit) {
        if let match = DistanceUnit.allCases.first(where: { $0.unitLength == unit }) { return (value, match) }
        return (Measurement(value: value, unit: unit).converted(to: .meters).value, .meters)
    }
}

extension Alert {
    init(_ alert: any WorkoutAlert, activity: Activity) throws(UnsupportedWorkout) {
        let usesPace = [.running, .walking, .hiking].contains(activity)
        let cadenceUnit: CadenceUnit = activity == .cycling ? .revolutionsPerMinute : .stepsPerMinute

        func speed(_ target: Target, _ metric: WorkoutAlertMetric) -> Alert {
            guard usesPace else {
                let perHour = SpeedUnit.kilometersPerHour.metersPerSecond
                return .speed(target.map { rounded($0 / perHour) }, .kilometersPerHour, Metric(metric))
            }
            // The fast end of a speed range is the low end of the pace range.
            let pace: Target = switch target {
            case .value(let speed): .value(rounded(1000 / speed))
            case .range(let speed): .range(rounded(1000 / speed.upperBound)...rounded(1000 / speed.lowerBound))
            }
            return .pace(pace, .perKilometer, Metric(metric))
        }

        switch alert {
        case let alert as SpeedThresholdAlert:
            self = speed(.value(alert.target.converted(to: .metersPerSecond).value), alert.metric)
        case let alert as SpeedRangeAlert:
            let range = alert.target.lowerBound.converted(to: .metersPerSecond).value
                ... alert.target.upperBound.converted(to: .metersPerSecond).value
            self = speed(.range(range), alert.metric)
        case let alert as HeartRateRangeAlert:
            self = .heartRate(Self.perMinute(alert.target.lowerBound)...Self.perMinute(alert.target.upperBound))
        case let alert as HeartRateZoneAlert:
            self = .heartRateZone(alert.zone)
        case let alert as PowerThresholdAlert:
            self = .power(.value(alert.target.converted(to: .watts).value), Metric(alert.metric))
        case let alert as PowerRangeAlert:
            let range = alert.target.lowerBound.converted(to: .watts).value
                ... alert.target.upperBound.converted(to: .watts).value
            self = .power(.range(range), Metric(alert.metric))
        case let alert as PowerZoneAlert:
            self = .powerZone(alert.zone)
        case let alert as CadenceThresholdAlert:
            self = .cadence(.value(Self.perMinute(alert.target)), cadenceUnit)
        case let alert as CadenceRangeAlert:
            self = .cadence(.range(Self.perMinute(alert.target.lowerBound)...Self.perMinute(alert.target.upperBound)),
                            cadenceUnit)
        default:
            throw .alert(String(describing: type(of: alert)))
        }
    }

    private static func perMinute(_ frequency: Measurement<UnitFrequency>) -> Double {
        rounded(frequency.converted(to: WorkoutAlertMetric.countPerMinute).value)
    }
}

extension Metric {
    init(_ metric: WorkoutAlertMetric) {
        self = metric == .average ? .average : .current
    }
}

extension Target {
    func map(_ transform: (Double) -> Double) -> Target {
        switch self {
        case .value(let value): .value(transform(value))
        case .range(let range): .range(transform(range.lowerBound)...transform(range.upperBound))
        }
    }
}

/// Speed and frequency conversions leave float noise (229.99999999999997); round it off to the hundredth.
private func rounded(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}
#endif
