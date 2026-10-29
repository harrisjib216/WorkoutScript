import Testing
import WorkoutScript

@Suite struct PrinterTests {
    @Test func printsTheStandardLayout() throws {
        let compiled = try #require(workout(examples["track-800s.wks"] ?? ""))
        #expect(compiled.script == """
            running outdoor "Track 800s"

            warmup 15min @ zone 2

            6x {
              800m @ 3:50-4:00/km "800"
              recover 400m
            }

            cooldown 10min

            """)
    }

    @Test func everyExampleSurvivesARoundTrip() throws {
        for (name, text) in examples {
            let compiled = try #require(workout(text), "\(name)")
            #expect(workout(compiled.script) == compiled, "\(name)")
        }
    }

    @Test func awkwardShapesSurviveARoundTrip() {
        let shapes = Workout(
            activity: .cycling, name: "Say \"hi\"",
            blocks: [
                Block(iterations: 1, intervals: [Interval(.work, Step()), Interval(.recovery, Step())]),
                Block(iterations: 1, intervals: [Interval(.work, Step(alert: .speed(.range(30...32.5), .kilometersPerHour, .average)))]),
                Block(iterations: 3, intervals: [Interval(.recovery, Step(goal: .time(1.5, .minutes), label: "Easy"))]),
            ])
        let printed = workout(shapes.script)
        #expect(printed?.blocks == shapes.blocks)
        #expect(printed?.name == "Say 'hi'")
    }
}
