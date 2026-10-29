import Testing
import WorkoutScript

@Suite struct CompilerTests {
    @Test func trackWorkout() throws {
        let compiled = try #require(workout(examples["track-800s.wks"] ?? ""))
        #expect(compiled == Workout(
            activity: .running, location: .outdoor, name: "Track 800s",
            warmup: Step(goal: .time(15, .minutes), alert: .heartRateZone(2)),
            blocks: [
                Block(iterations: 6, intervals: [
                    Interval(.work, Step(goal: .distance(800, .meters), alert: .pace(.range(230...240), .perKilometer, .current), label: "800")),
                    Interval(.recovery, Step(goal: .distance(400, .meters))),
                ]),
            ],
            cooldown: Step(goal: .time(10, .minutes))))
    }

    @Test func everyExampleCompilesCleanly() {
        #expect(examples.count >= 5)
        for (name, text) in examples {
            #expect(diagnostics(text).isEmpty, "\(name)")
        }
    }

    @Test func pacesReadEitherWayRound() {
        #expect(workout("running\n1km @ 4:00-3:50/km") == workout("running\n1km @ 3:50-4:00/km"))
        // A plain number is minutes: 4.5/km is 4:30/km.
        #expect(workout("running\n1km @ 4.5/km")?.blocks.first?.intervals.first?.step.alert == .pace(.value(270), .perKilometer, .current))
    }

    @Test func unitsCanBeSeparateWords() {
        #expect(workout("cycling\n10 min @ 140-150 bpm") == workout("cycling\n10min @ 140-150bpm"))
        #expect(workout("running\n5k") == workout("running\n5km"))
    }

    @Test func repeatsComeInThreeShapes() {
        let block = Block(iterations: 4, intervals: [
            Interval(.work, Step(goal: .distance(1, .kilometers))),
            Interval(.recovery, Step(goal: .time(90, .seconds))),
        ])
        #expect(workout("running\n4x {\n  1km\n  recover 90s\n}")?.blocks == [block])
        #expect(workout("running\n4 x { 1km, recover 90s }")?.blocks == [block])
        #expect(workout("running\n4x 1km")?.blocks == [Block(iterations: 4, intervals: [Interval(.work, Step(goal: .distance(1, .kilometers)))])])
    }

    @Test func goalsAndTargets() {
        let steps = workout("""
            cycling outdoor
            open @ power zone 3
            20min @ avg 240-260W
            100m in 1:45
            300kcal @ 85-95rpm
            1:30:00 @ 28km/h
            """)?.blocks.map { $0.intervals[0].step }
        #expect(steps == [
            Step(goal: .open, alert: .powerZone(3)),
            Step(goal: .time(20, .minutes), alert: .power(.range(240...260), .average)),
            Step(goal: .poolSwim(100, .meters, seconds: 105)),
            Step(goal: .energy(300, .kilocalories), alert: .cadence(.range(85...95), .revolutionsPerMinute)),
            Step(goal: .time(5400, .seconds), alert: .speed(.value(28), .kilometersPerHour, .current)),
        ])
    }

    @Test(arguments: [
        ("warmup 10min", "1:1: error: a script starts with its activity, like running outdoor"),
        ("runing outdoor", "1:1: error: unknown activity 'runing'; did you mean 'running'?"),
        ("running outdor", "1:9: error: unknown location 'outdor'; did you mean 'outdoor'?"),
        ("running", "1:1: error: this workout has no steps yet; add one, like 6x 400m"),
        ("running\nwarmpu 10min", "2:1: error: unknown step 'warmpu'; did you mean 'warmup'?"),
        ("running\n4x {\n  recovr 2min\n}", "3:3: error: unknown step 'recovr'; did you mean 'recover'?"),
        ("running\n10", "2:1: error: 10 needs a unit: a time (10min), a distance (2km) or open"),
        ("running\n10mn", "2:3: error: unknown unit 'mn'; did you mean 'min'?"),
        ("running\n4:00/km", "2:1: error: 4:00/km is a pace; pace targets go after @, like 1km @ 4:00/km"),
        ("running\n0km", "2:1: error: a goal has to be more than zero"),
        ("running\n1km @ 4:00/kn", "2:11: error: unknown unit '/kn'; did you mean '/km'?"),
        ("running\n1km @ 4:00", "2:7: error: this target needs a unit: /km or /mi for pace, km/h or mph for speed, bpm, W, spm or rpm"),
        ("running\n1km @ 4:00/km-4:10/mi", "2:7: error: both ends of a range need the same unit"),
        ("running\n1km @ 150bpm", "2:7: error: heart rate targets need a range or a zone, like 145-155bpm or zone 2"),
        ("running\n1km @ zone 6", "2:12: error: heart rate zones run from 1 to 5"),
        ("running\n1km @ avg zone 2", "2:7: error: avg works with pace, speed and power targets"),
        ("running\n1km @ 1:30W", "2:7: error: 1:30W is a clock time; only pace targets use minutes:seconds"),
        ("running\n1km @ 10min", "2:7: error: 10min is a goal, not a target; the goal goes before @"),
        ("running\n1km 2km", "2:5: error: a step has one goal; put the next step on its own line"),
        ("running\n0x 1km", "2:1: error: a repeat count is a whole number, 1 or more"),
        ("running\n6x", "2:1: error: a repeat needs steps, like 6x 400m or 6x { 400m, recover 200m }"),
        ("running\n6x {\n}", "2:1: error: this repeat has no steps"),
        ("running\n6x {\n 1km", "2:4: error: this repeat is missing its closing }"),
        ("running\n6x { 2x 1km }", "2:6: error: repeats can't be nested; WorkoutKit runs one level of repeats"),
        ("running\n6x { warmup }", "2:6: error: the warmup goes outside the repeat"),
        ("running\n1km\nwarmup", "3:1: error: the warmup has to come before the intervals"),
        ("running\n1km\n}", "3:1: error: there's no repeat for this } to close"),
        ("running\n1km \"Fast", "2:5: error: this label is missing its closing quote"),
    ])
    func errors(script: String, expected: String) {
        #expect(diagnostics(script) == [expected])
    }

    @Test func secondWarmupPointsAtTheFirst() throws {
        let result = Compiler.compile("running\nwarmup 5min\nwarmup 10min\n1km")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.message == "this workout already has a warmup")
        #expect(diagnostic.notes.map { result.file.position(of: $0.range.lowerBound).line } == [2])
        #expect(result.workout == nil)
    }

    @Test func nothingAfterTheCooldown() {
        #expect(diagnostics("running\ncooldown\n1km") == ["3:1: error: nothing can come after the cooldown"])
    }

    @Test func shortMeterGoalsGetAWarningAndAFixIt() throws {
        let result = Compiler.compile("running\nwarmup 10m\n1km")
        let warning = try #require(result.diagnostics.first)
        #expect(warning.severity == .warning)
        #expect(warning.message == "10m is 10 meters; for minutes, write min")
        #expect(warning.fixIt == FixIt(replacing: SourceRange(17, 18), with: "min"))
        // A warning alone doesn't stop the workout compiling, and swimmers can write 25m.
        #expect(result.workout != nil)
        #expect(diagnostics("swimming\n4x 25m").isEmpty)
    }

    @Test func oneErrorPerBrokenLine() {
        #expect(diagnostics("running\n6x {\n  1km @ 150bpm\n  recover 400m @ 3:50/kn\n}\ncooldown") == [
            "3:9: error: heart rate targets need a range or a zone, like 145-155bpm or zone 2",
            "4:22: error: unknown unit '/kn'; did you mean '/km'?",
        ])
    }

    @Test func platformChecksPointAtTheText() {
        struct NoPower: WorkoutPlatform {
            func supports(_ activity: Activity, location: Location?) -> Bool { true }
            func supports(_ goal: Goal, for activity: Activity, location: Location?) -> Bool { goal.kindName != "energy" }
            func supports(_ alert: Alert, for activity: Activity, location: Location?) -> Bool { alert.kindName != "power" }
        }
        #expect(diagnostics("running indoor\n20min @ 250W\n300kcal", platform: NoPower()) == [
            "2:9: error: WorkoutKit doesn't support power alerts for indoor running",
            "3:1: error: WorkoutKit doesn't support energy goals for indoor running",
        ])
    }

    @Test func diagnosticsRenderLikeSwiftc() {
        let result = Compiler.compile("running\n1km @ 150bpm", name: "tempo.wks")
        #expect(result.diagnostics.first?.rendered(in: result.file) == """
            tempo.wks:2:7: error: heart rate targets need a range or a zone, like 145-155bpm or zone 2
            1km @ 150bpm
                  ^~~~~~
                  145-155bpm
            """)
    }
}
