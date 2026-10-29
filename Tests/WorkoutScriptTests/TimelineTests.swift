import Testing
import WorkoutScript

@Suite struct TimelineTests {
    @Test func repeatsAreExpanded() throws {
        let timeline = try #require(workout(examples["track-800s.wks"] ?? "")).timeline
        #expect(timeline.count == 14)
        #expect(timeline.map(\.kind).prefix(3) == [.warmup, .work, .recovery])
        #expect(timeline[1].iteration == 1)
        #expect(timeline[12].iteration == 6)
        #expect(timeline.last?.kind == .cooldown)
    }

    @Test func paceRangesFlipIntoSpeedRanges() throws {
        // 3:50/km is the fast end, so it is the top of the speed range.
        let speed = try #require(Alert.pace(.range(230...240), .perKilometer, .current).metersPerSecond)
        #expect(abs(speed.lowerBound - 1000.0 / 240) < 1e-9)
        #expect(abs(speed.upperBound - 1000.0 / 230) < 1e-9)
    }

    @Test func distancesAreEstimatedFromTheirTargets() throws {
        let fast = Step(goal: .distance(800, .meters), alert: .pace(.value(240), .perKilometer, .current))
        #expect(abs(try #require(fast.estimatedSeconds) - 192) < 1e-9)
        let ride = Step(goal: .distance(10, .kilometers), alert: .speed(.value(30), .kilometersPerHour, .current))
        #expect(abs(try #require(ride.estimatedSeconds) - 1200) < 1e-9)
        #expect(Step(goal: .distance(400, .meters)).estimatedSeconds == nil)
    }

    @Test func totals() throws {
        let compiled = try #require(workout(examples["sweet-spot.wks"] ?? ""))
        // Warmup 10, three times 12 + 5, cooldown 10: 71 minutes.
        let expected: Double = 71 * 60
        #expect(compiled.estimatedDuration.seconds == expected)
        #expect(compiled.estimatedDuration.unknownSteps == 0)
        #expect(try #require(workout(examples["track-800s.wks"] ?? "")).totalMeters == 7200)
    }
}
