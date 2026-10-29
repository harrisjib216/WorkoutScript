import Foundation
import WorkoutScript

/// The scripts in Examples/, by file name.
let examples: [String: String] = {
    let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Examples")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    var scripts: [String: String] = [:]
    for name in names where name.hasSuffix(".wks") {
        scripts[name] = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }
    return scripts
}()

/// Compiles a script that is expected to be valid.
func workout(_ text: String) -> Workout? {
    Compiler.compile(text).workout
}

/// Each diagnostic as `line:column: severity: message`, which reads well in a failed expectation.
func diagnostics(_ text: String, platform: (any WorkoutPlatform)? = nil) -> [String] {
    let result = Compiler.compile(text, platform: platform)
    return result.diagnostics.map { diagnostic in
        let (line, column) = result.file.position(of: diagnostic.range.lowerBound)
        return "\(line):\(column): \(diagnostic.severity.rawValue): \(diagnostic.message)"
    }
}
