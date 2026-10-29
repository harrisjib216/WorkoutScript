#if canImport(WorkoutKit)
import Foundation
import Testing
import WorkoutKit
import WorkoutScript
import WorkoutScriptKit

@Suite struct WorkoutKitTests {
    private let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Examples")

    private func example(_ name: String) throws -> Workout {
        let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        return try #require(Compiler.compile(text, platform: .workoutKit).workout)
    }

    @Test func compilesToTheCustomWorkoutYouWouldWriteByHand() throws {
        let expected = CustomWorkout(
            activity: .running, location: .outdoor, displayName: "Track 800s",
            warmup: WorkoutStep(goal: .time(15, .minutes), alert: .heartRate(zone: 2)),
            blocks: [
                IntervalBlock(steps: [
                    IntervalStep(.work, step: WorkoutStep(
                        goal: .distance(800, .meters),
                        alert: .speed((1000.0 / 240)...(1000.0 / 230), unit: .metersPerSecond, metric: .current),
                        displayName: "800")),
                    IntervalStep(.recovery, goal: .distance(400, .meters)),
                ], iterations: 6),
            ],
            cooldown: WorkoutStep(goal: .time(10, .minutes)))
        #expect(try example("track-800s.wks").customWorkout == expected)
    }

    @Test func everyExampleSurvivesAWorkoutFile() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".wks") }
        #expect(names.count >= 5)
        for name in names {
            let workout = try example(name)
            let data = try workout.workoutPlan().dataRepresentation
            guard case .custom(let custom) = try WorkoutPlan(from: data).workout else {
                Issue.record("\(name) didn't come back as a custom workout")
                continue
            }
            #expect(try Workout(custom) == workout, "\(name)")
        }
    }

    @Test(arguments: [
        ("running indoor\n20min @ 250W", "WorkoutKit doesn't support power alerts for indoor running"),
        ("running indoor\n20min @ 170-180spm", "WorkoutKit doesn't support cadence alerts for indoor running"),
        ("walking\n1km @ 6:00/km", "WorkoutKit doesn't support pace alerts for walking"),
        ("swimming\n100m @ zone 2\n100m @ 1:45/km", "WorkoutKit doesn't support pace alerts for swimming"),
        ("rowing indoor\n2km", "WorkoutKit doesn't support distance goals for indoor rowing"),
        ("running outdoor\n300kcal", "WorkoutKit doesn't support energy goals for outdoor running"),
        ("running\n100m in 1:45", "WorkoutKit doesn't support pool swim goals for running"),
    ])
    func workoutKitDecidesWhatIsSupported(script: String, message: String) {
        let result = Compiler.compile(script, platform: .workoutKit)
        #expect(result.diagnostics.map(\.message) == [message])
        #expect(result.workout == nil)
    }

    @Test func speedComesBackAsPaceForRunners() throws {
        let running = Workout(activity: .running, blocks: [
            Block(intervals: [Interval(.work, Step(alert: .speed(.value(12), .kilometersPerHour, .current)))]),
        ])
        let back = try Workout(running.customWorkout)
        #expect(back.blocks[0].intervals[0].step.alert == .pace(.value(300), .perKilometer, .current))
    }
}
#endif
