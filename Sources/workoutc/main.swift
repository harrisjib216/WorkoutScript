import Foundation
import WorkoutScript
import WorkoutScriptKit

#if canImport(WorkoutKit)
import WorkoutKit
#endif

let usage = """
    usage: workoutc check <script.wks>...                  report errors and warnings, and summarize each workout
           workoutc export <script.wks> [-o <file.workout>] compile to a .workout file the iPhone opens
           workoutc print <file.workout>                    print a .workout file as a script
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Compiles a file and prints its diagnostics. Checks against WorkoutKit wherever WorkoutKit exists.
func compile(_ path: String) -> Compilation {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("workoutc: can't read \(path)") }
    #if canImport(WorkoutKit)
    let result = Compiler.compile(text, name: path, platform: .workoutKit)
    #else
    let result = Compiler.compile(text, name: path)
    #endif
    for diagnostic in result.diagnostics {
        FileHandle.standardError.write(Data((diagnostic.rendered(in: result.file) + "\n").utf8))
    }
    return result
}

func summary(_ workout: Workout) -> String {
    let (seconds, unknown) = workout.estimatedDuration
    var parts = [workout.name.map { "\"\($0)\"" } ?? "untitled",
                 [workout.location?.rawValue, workout.activity.rawValue].compactMap { $0 }.joined(separator: " "),
                 "\(workout.timeline.count) steps"]
    if seconds > 0 { parts.append("about \(Int((seconds / 60).rounded())) min" + (unknown > 0 ? " plus \(unknown) open" : "")) }
    if workout.totalMeters > 0 { parts.append(String(format: "%.1f km", workout.totalMeters / 1000)) }
    return parts.joined(separator: ", ")
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
arguments.removeFirst()

switch command {
case "check":
    guard !arguments.isEmpty else { fail(usage) }
    var failed = false
    for path in arguments {
        let result = compile(path)
        if let workout = result.workout {
            print("\(path): \(summary(workout))")
        } else {
            failed = true
        }
    }
    exit(failed ? 1 : 0)

#if canImport(WorkoutKit)
case "export":
    guard let path = arguments.first else { fail(usage) }
    var output = (path as NSString).deletingPathExtension + ".workout"
    if let flag = arguments.firstIndex(of: "-o"), flag + 1 < arguments.count { output = arguments[flag + 1] }
    guard let workout = compile(path).workout else { exit(1) }
    do {
        try workout.workoutPlan().dataRepresentation.write(to: URL(fileURLWithPath: output))
        print("wrote \(output): \(summary(workout))")
    } catch {
        fail("workoutc: couldn't write \(output): \(error)")
    }

case "print":
    guard let path = arguments.first, let data = FileManager.default.contents(atPath: path) else { fail(usage) }
    do {
        let plan = try WorkoutPlan(from: data)
        guard case .custom(let custom) = plan.workout else { fail("workoutc: \(path) is not a custom workout") }
        print(try Workout(custom).script, terminator: "")
    } catch {
        fail("workoutc: can't read \(path) as a workout: \(error)")
    }
#endif

default:
    fail(usage)
}
