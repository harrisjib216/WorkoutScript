import Foundation
import Observation
import WorkoutScript
import WorkoutScriptKit

@MainActor @Observable
final class EditorModel {
    /// The script, saved as it changes so it's still there next launch.
    var text: String {
        didSet {
            UserDefaults.standard.set(text, forKey: "script")
            compile()
        }
    }

    private(set) var compilation: Compilation
    /// The last workout that compiled. It stays on screen while the script has errors, so the shape above the
    /// editor doesn't vanish on every keystroke.
    private(set) var workout: Workout?

    init(text: String = UserDefaults.standard.string(forKey: "script") ?? Sample.all[0].text) {
        self.text = text
        compilation = Compiler.compile(text, platform: .workoutKit)
        workout = compilation.workout
    }

    /// True when the workout on screen is from an earlier version of the script.
    var isStale: Bool { compilation.workout == nil && workout != nil }

    func apply(_ fixIt: FixIt) {
        text.replaceSubrange(compilation.file.indices(of: fixIt.range), with: fixIt.replacement)
    }

    private func compile() {
        compilation = Compiler.compile(text, platform: .workoutKit)
        if let compiled = compilation.workout { workout = compiled }
    }
}
