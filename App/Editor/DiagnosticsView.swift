import SwiftUI
import WorkoutScript

/// The compiler's errors and warnings. Tapping one selects the text it's about; a fix-it button applies the
/// compiler's suggested edit.
struct DiagnosticsView: View {
    var compilation: Compilation
    var onSelect: (SourceRange) -> Void
    var onFix: (FixIt) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(compilation.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    row(diagnostic)
                }
            }
            .padding()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ diagnostic: Diagnostic) -> some View {
        let line = compilation.file.position(of: diagnostic.range.lowerBound).line
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Line \(line)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    + Text("  ") + Text(diagnostic.message).font(.callout)
                if let fixIt = diagnostic.fixIt {
                    Button {
                        onFix(fixIt)
                    } label: {
                        Text(fixIt.replacement.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.callout.monospaced())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Apply fix: \(fixIt.replacement)")
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .onTapGesture { onSelect(diagnostic.range) }
        .accessibilityAction(named: "Show in script") { onSelect(diagnostic.range) }
    }
}
