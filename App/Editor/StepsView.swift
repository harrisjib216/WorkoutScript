import SwiftUI
import WorkoutScript

/// The workout the way the Watch will run it: warmup, each block with its repeat count, cooldown.
struct StepsView: View {
    var workout: Workout

    var body: some View {
        List {
            if let warmup = workout.warmup {
                Section("Warmup") { StepRow(kind: .warmup, step: warmup) }
            }
            ForEach(Array(workout.blocks.enumerated()), id: \.offset) { index, block in
                Section(block.iterations > 1 ? "Repeat \(block.iterations)×" : "Block \(index + 1)") {
                    ForEach(Array(block.intervals.enumerated()), id: \.offset) { _, interval in
                        StepRow(kind: interval.purpose == .work ? .work : .recovery, step: interval.step)
                    }
                }
            }
            if let cooldown = workout.cooldown {
                Section("Cooldown") { StepRow(kind: .cooldown, step: cooldown) }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct StepRow: View {
    var kind: TimelineEntry.Kind
    var step: Step

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(kind.color)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label ?? kind.title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let seconds = step.estimatedSeconds {
                Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let goal = step.goal == .open ? "Open" : step.goal.scriptText
        guard let alert = step.alert else { return goal }
        return "\(goal) @ \(alert.scriptText)"
    }
}
