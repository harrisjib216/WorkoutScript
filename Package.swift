// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkoutScript",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "WorkoutScript", targets: ["WorkoutScript"]),
        .library(name: "WorkoutScriptKit", targets: ["WorkoutScriptKit"]),
        .executable(name: "workoutc", targets: ["workoutc"]),
    ],
    targets: [
        // The language: lexer, parser, diagnostics and the workout model. Plain Swift, so it also builds on Linux.
        .target(name: "WorkoutScript"),
        // The bridge to Apple's WorkoutKit: CustomWorkout, WorkoutPlan and WorkoutKit's own support checks.
        .target(name: "WorkoutScriptKit", dependencies: ["WorkoutScript"]),
        // Command-line compiler: check scripts, export .workout files, print .workout files as scripts.
        .executableTarget(name: "workoutc", dependencies: ["WorkoutScript", "WorkoutScriptKit"]),
        .testTarget(name: "WorkoutScriptTests", dependencies: ["WorkoutScript"]),
        .testTarget(name: "WorkoutScriptKitTests", dependencies: ["WorkoutScriptKit"]),
    ]
)
