import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 14) {
                        Image("logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tissue Box Guide")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("Quick sketching like on a café napkin — everything you need at a glance.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 2)

                    // Drawing Tools
                    helpCard("Drawing Tools", icon: "paintbrush.pointed") {
                        ToolGuideRow(icon: "pencil.tip", color: .blue, title: "Pen", key: "P",
                                     detail: "Smooth vector strokes with 8 theme-adaptive colors and adjustable width.")
                        Divider().opacity(0.4)
                        ToolGuideRow(icon: "pencil", color: .orange, title: "Sharpie", key: "S",
                                     detail: "Bold two-pass glow/core stroke with its own independent color presets.")
                        Divider().opacity(0.4)
                        ToolGuideRow(icon: "drop.fill", color: .teal, title: "Fill", key: "F",
                                     detail: "Tap inside any closed shape to fill it cleanly without bleeding. Adjust opacity and gap-closing tolerance.")
                        Divider().opacity(0.4)
                        ToolGuideRow(icon: "eraser", color: .pink, title: "Eraser", key: "E",
                                     detail: "Switch between Full Stroke and Partial erase, or target All, Pen, or Sharpie only.")
                        Divider().opacity(0.4)
                        ToolGuideRow(icon: "cursorarrow.click", color: .purple, title: "Select", key: "⇧S",
                                     detail: "Draw a lasso to select strokes, fills, and images. Drag to move, double-tap for Copy/Paste/Delete.")
                    }

                    // Keyboard Shortcuts
                    helpCard("Keyboard Shortcuts", icon: "keyboard") {
                        VStack(alignment: .leading, spacing: 10) {
                            shortcutSubgroup("Canvas & Colors", rows: [
                                ("Color preset 1–8", "1 – 8"),
                                ("Toggle toolbar", "Tab"),
                                ("Undo / Redo", "⌘Z / ⌘⇧Z"),
                                ("Copy / Paste", "⌘C / ⌘V"),
                                ("Delete selected", "⌫"),
                                ("Import image", "⌘I"),
                                ("Resize selected image", "⌘+ / ⌘-"),
                            ])
                            Divider().opacity(0.4)
                            shortcutSubgroup("Files & Library", rows: [
                                ("New tissue", "⌘N"),
                                ("Search tissues", "⌘F"),
                                ("Select all tissues", "⌘A"),
                                ("Save / Open .wb", "⌘S / ⌘O"),
                                ("Close tissue", "⌘W"),
                            ])
                        }
                    }

                    // Tips & Gestures
                    helpCard("Gestures & Tips", icon: "hand.draw") {
                        TipRow(icon: "hand.point.up.left", text: "Tap a tool to open its color, width, opacity, or eraser options.")
                        Divider().opacity(0.4)
                        TipRow(icon: "applepencil", text: "Apple Pencil double-tap toggles the eraser; squeeze hides/shows the toolbar.")
                        Divider().opacity(0.4)
                        TipRow(icon: "arrow.up.left.and.arrow.down.right", text: "Scroll (Mac) or two-finger drag (iPad) to pan the infinite canvas; pinch to zoom.")
                        Divider().opacity(0.4)
                        TipRow(icon: "square.and.arrow.up", text: "Export any tissue as portable .wb, transparent high-DPI PNG, or vector PDF from the More menu.")
                    }

                    // About & License
                    helpCard("About & License", icon: "info.circle") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open-source under the MIT License")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Copyright © 2025-2026 Piyush Itankar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Link(destination: AboutView.repoURL) {
                                Label("GitHub", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .liquidGlassInteractiveCapsule()
                            }
                            .pointingHand()
                        }
                    }
                }
                .padding(22)
            }
            .navigationTitle("Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .pointingHand()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 580)
    }

    private func helpCard<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    private func shortcutSubgroup(_ heading: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            ForEach(rows, id: \.0) { title, key in
                HStack {
                    Text(title)
                        .font(.system(size: 13))
                    Spacer()
                    Keycap(key)
                }
            }
        }
    }
}

private struct ToolGuideRow: View {
    let icon: String
    let color: Color
    let title: String
    let key: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Keycap(key)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
