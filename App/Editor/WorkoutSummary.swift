import SwiftUI
import WorkoutScript

/// The workout's name, length and shape: one bar per step, as wide as the step is long and as tall as it is hard.
struct WorkoutSummary: View {
    var workout: Workout
    var isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(subtitle, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isStale {
                    Text("Last version that compiled")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            WorkoutShape(timeline: workout.timeline)
                .frame(height: 56)
                .opacity(isStale ? 0.4 : 1)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private var subtitle: String {
        var parts = [[workout.location?.rawValue.capitalized, workout.activity.rawValue]
            .compactMap { $0 }.joined(separator: " ")]
        let (seconds, unknown) = workout.estimatedDuration
        if seconds > 0 {
            let minutes = Int((seconds / 60).rounded())
            parts.append(unknown > 0 ? "\(minutes)+ min" : "\(minutes) min")
        }
        if workout.totalMeters > 0 {
            parts.append(workout.totalMeters.formatted(.number.precision(.fractionLength(0...1)).scale(0.001)) + " km")
        }
        parts.append("\(workout.timeline.count) steps")
        return parts.joined(separator: " · ")
    }

    private var symbol: String {
        switch workout.activity {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairs: "figure.stair.stepper"
        case .hiit: "figure.highintensity.intervaltraining"
        }
    }
}

struct WorkoutShape: View {
    var timeline: [TimelineEntry]

    var body: some View {
        GeometryReader { proxy in
            let widths = barWidths(total: proxy.size.width)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(timeline) { entry in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.kind.color)
                        .frame(width: widths[entry.id], height: proxy.size.height * entry.kind.height)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement()
        .accessibilityLabel("Workout shape")
        .accessibilityValue(accessibilityDescription)
    }

    /// Steps with no estimate (open goals, distances with no pace) get the typical step's width.
    private func barWidths(total: CGFloat) -> [CGFloat] {
        let known = timeline.compactMap(\.estimatedSeconds).sorted()
        let fallback = known.isEmpty ? 60 : known[known.count / 2]
        let seconds = timeline.map { $0.estimatedSeconds ?? fallback }
        let sum = seconds.reduce(0, +)
        let available = total - CGFloat(max(timeline.count - 1, 0)) * 2
        return seconds.map { max(CGFloat($0 / sum) * available, 2) }
    }

    private var accessibilityDescription: String {
        let work = timeline.filter { $0.kind == .work }.count
        let recovery = timeline.filter { $0.kind == .recovery }.count
        return "\(work) work steps and \(recovery) recoveries"
    }
}

extension TimelineEntry.Kind {
    var color: Color {
        switch self {
        case .warmup, .cooldown: .secondary.opacity(0.45)
        case .work: .accentColor
        case .recovery: .blue.opacity(0.55)
        }
    }

    var height: CGFloat {
        switch self {
        case .warmup, .cooldown: 0.4
        case .work: 1
        case .recovery: 0.3
        }
    }

    var title: String {
        switch self {
        case .warmup: "Warmup"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cooldown"
        }
    }
}
