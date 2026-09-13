import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Tools") {
                    ShortcutRow("Pen", key: "P")
                    ShortcutRow("Eraser", key: "E")
                    ShortcutRow("Selection", key: "S")
                    ShortcutRow("Pen color 1–8", key: "1 – 8")
                }

                Section("Edit") {
                    ShortcutRow("Undo", key: "⌘Z")
                    ShortcutRow("Redo", key: "⌘⇧Z")
                    ShortcutRow("Delete selected", key: "⌫")
                }

                Section("File") {
                    ShortcutRow("Save", key: "⌘S")
                    ShortcutRow("Open", key: "⌘O")
                    ShortcutRow("Close board", key: "⌘W")
                }

                Section("View") {
                    ShortcutRow("Toggle toolbar", key: "Tab")
                    ShortcutRow("Open tool settings", key: "Double-tap tool")
                    ShortcutRow("Center canvas", key: "Settings → Center")
                }

                Section("Canvas") {
                    FeatureRow("Pen", "Draw with configurable color, thickness and smoothness. Double-tap the pen button for settings.")
                    FeatureRow("Eraser", "Two modes: Partial (splits strokes) and Full Stroke (removes entire stroke). Size adjustable.")
                    FeatureRow("Selection", "Draw a lasso to select strokes. Drag to move, delete with ⌫.")
                }

                Section("Export") {
                    FeatureRow(".wb format", "Saves all strokes as JSON. Open via File → Open or the welcome screen.")
                    FeatureRow("PNG / PDF", "Export the canvas as a high-resolution image or vector PDF. Cropped to content.")
                }

                Section("Doodles") {
                    FeatureRow("Auto-save", "All boards are saved automatically to the central board library.")
                    FeatureRow("Welcome screen", "Create, rename, delete, and open boards from the welcome screen.")
                }
            }
            #if os(macOS)
            .listStyle(.bordered)
            #else
            .listStyle(.grouped)
            #endif
            .navigationTitle("Help & Shortcuts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

private struct ShortcutRow: View {
    let title: String
    let key: String

    init(_ title: String, key: String) {
        self.title = title
        self.key = key
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(key)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

private struct FeatureRow: View {
    let title: String
    let description: String

    init(_ title: String, _ description: String) {
        self.title = title
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body)
            Text(description).font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
