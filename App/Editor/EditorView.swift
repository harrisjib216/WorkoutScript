import SwiftUI
import WorkoutKit
import WorkoutScript
import WorkoutScriptKit

struct EditorView: View {
    private enum Page: String, CaseIterable {
        case script = "Script"
        case steps = "Steps"
    }

    @State private var model = EditorModel()
    @AppStorage("page") private var page = Page.script
    @State private var selection: TextSelection?
    @State private var previewPlan: WorkoutPlan?
    @State private var showingPreview = false
    @State private var showingSchedule = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let workout = model.workout {
                    WorkoutSummary(workout: workout, isStale: model.isStale)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }
                Picker("Page", selection: $page) {
                    ForEach(Page.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch page {
                case .script:
                    editor
                case .steps:
                    if let workout = model.workout {
                        StepsView(workout: workout)
                    } else {
                        ContentUnavailableView("No steps yet", systemImage: "figure.run",
                                               description: Text("Fix the script's errors to see its steps."))
                    }
                }
            }
            .navigationTitle(model.workout?.name ?? "WorkoutScript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .workoutPreview(previewPlan ?? Self.emptyPlan, isPresented: $showingPreview)
            #if DEBUG
            // For README screenshots: `-previewOnLaunch YES` opens the Watch preview straight away.
            .task {
                if UserDefaults.standard.bool(forKey: "previewOnLaunch"), let workout = model.compilation.workout {
                    previewPlan = workout.workoutPlan()
                    showingPreview = true
                }
            }
            #endif
            .sheet(isPresented: $showingSchedule) {
                if let workout = model.compilation.workout {
                    ScheduleView(workout: workout)
                }
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.text, selection: $selection)
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
                .accessibilityLabel("Workout script")

            if !model.compilation.diagnostics.isEmpty {
                DiagnosticsView(compilation: model.compilation, onSelect: select, onFix: model.apply)
                    .frame(maxHeight: 220)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(Sample.all) { sample in
                    Button(sample.name) { model.text = sample.text }
                }
            } label: {
                Label("Examples", systemImage: "list.bullet.rectangle")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let workout = model.compilation.workout {
                ShareLink(item: WorkoutFile(workout: workout), preview: SharePreview(workout.name ?? "Workout")) {
                    Label("Share .workout file", systemImage: "square.and.arrow.up")
                }
                Menu {
                    Button("Preview on Apple Watch", systemImage: "applewatch") {
                        previewPlan = workout.workoutPlan()
                        showingPreview = true
                    }
                    Button("Schedule…", systemImage: "calendar.badge.plus") { showingSchedule = true }
                } label: {
                    Label("Send to Watch", systemImage: "applewatch")
                }
            }
        }
    }

    /// Selects the text a diagnostic points at, so tapping an error jumps to it.
    private func select(_ range: SourceRange) {
        page = .script
        editorFocused = true
        selection = TextSelection(range: model.compilation.file.indices(of: range))
    }

    private static let emptyPlan = WorkoutPlan(.custom(CustomWorkout(activity: .running)))
}

/// A `.workout` file: WorkoutKit's own encoding, which the iPhone opens and offers to add to the Watch.
struct WorkoutFile: Transferable {
    var workout: Workout

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { file in
            try file.workout.workoutPlan().dataRepresentation
        }
        .suggestedFileName { "\($0.workout.name ?? "Workout").workout" }
    }
}

#Preview {
    EditorView()
}
