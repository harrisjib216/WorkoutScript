import SwiftUI
import WorkoutKit
import WorkoutScript
import WorkoutScriptKit

/// Puts the workout on the Watch's schedule with WorkoutScheduler.
struct ScheduleView: View {
    var workout: Workout

    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var status: String?
    @State private var isScheduling = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("When", selection: $date, in: Date.now...)
                if let status {
                    Text(status).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(workout.name ?? "Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") { Task { await schedule() } }.disabled(isScheduling)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func schedule() async {
        guard WorkoutScheduler.isSupported else {
            status = "Scheduling needs an iPhone paired with an Apple Watch."
            return
        }
        isScheduling = true
        defer { isScheduling = false }
        guard await Self.authorize() else {
            status = "Allow scheduling in Settings to send workouts to your Watch."
            return
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        await WorkoutScheduler.shared.schedule(workout.workoutPlan(), at: components)
        dismiss()
    }

    /// Asks off the main actor and hands back a Bool, because older SDKs don't mark AuthorizationState Sendable.
    private nonisolated static func authorize() async -> Bool {
        await WorkoutScheduler.shared.requestAuthorization() == .authorized
    }
}
