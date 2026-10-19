import AppKit
import SwiftUI

extension TagColor {
    var title: String { finderName }

    var color: Color {
        switch self {
        case .red: Color(red: 0.98, green: 0.33, blue: 0.33)
        case .orange: Color(red: 0.99, green: 0.60, blue: 0.20)
        case .yellow: Color(red: 0.99, green: 0.80, blue: 0.20)
        case .green: Color(red: 0.36, green: 0.80, blue: 0.40)
        case .blue: Color(red: 0.25, green: 0.56, blue: 0.98)
        case .purple: Color(red: 0.70, green: 0.42, blue: 0.86)
        case .gray: Color(red: 0.62, green: 0.62, blue: 0.64)
        }
    }

    /// A colored dot for menus (menus otherwise draw their icons in one color).
    var menuImage: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// The little overlapping dots next to a name, like Finder.
struct TagDots: View {
    let tags: [TagColor]
    var size: CGFloat = 8

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: -size * 0.35) {
                ForEach(tags) { tag in
                    Circle()
                        .fill(tag.color)
                        .frame(width: size, height: size)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                }
            }
            .help(tags.map(\.title).joined(separator: ", "))
        }
    }
}

/// Right-click → Tags: the seven colors (checked when everything chosen has it), and Remove Tags.
struct TagMenu: View {
    @EnvironmentObject var store: Store
    let targets: Set<Selectable>

    var body: some View {
        Menu("Tags") {
            ForEach(TagColor.allCases) { tag in
                Toggle(isOn: Binding(get: { store.allHave(tag, targets) }, set: { _ in store.toggleTag(tag, on: targets) })) {
                    Label { Text(tag.title) } icon: { Image(nsImage: tag.menuImage) }
                }
            }
            Divider()
            Button("Remove Tags") { store.clearTags(on: targets) }
                .disabled(targets.allSatisfy { store.tags(of: $0).isEmpty })
        }
    }
}

/// Rename N Items: a name and a starting number, with a preview — like Finder's "Name and Index".
struct BatchRenamePrompt: View {
    @EnvironmentObject var store: Store
    let targets: Set<Selectable>
    @State private var base = ""
    @State private var start = 1

    private var count: Int {
        targets.filter { if case .item(let id) = $0 { store.items.first { $0.id == id }?.kind != .text } else { true } }.count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename \(count) Items")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 8) {
                    RenameField(initial: suggestedBase, onChange: { base = $0 },
                                commit: { base = $0; apply() }, cancel: close)
                        .frame(height: 22)
                    Text("starting at")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Stepper(value: $start, in: 0...9999) {
                        Text("\(start)").font(.system(size: 12)).monospacedDigit().frame(minWidth: 22)
                    }
                    .fixedSize()
                }
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack {
                    Text("Notes keep their names (they're named by their text).")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary).frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    Button(action: apply) {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor).frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(base.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            )
        }
        .onAppear { base = suggestedBase }
    }

    /// The first one's name without its number or file type, as a starting point.
    private var suggestedBase: String {
        guard let first = store.visibleOrder.first(where: targets.contains) else { return "" }
        var name: String
        switch first {
        case .folder(let id): name = store.folder(id)?.name ?? ""
        case .item(let id): name = ((store.items.first { $0.id == id }?.displayTitle ?? "") as NSString).deletingPathExtension
        }
        while let last = name.last, last.isNumber || last == " " { name.removeLast() }
        return name
    }

    private var preview: String {
        let name = base.trimmingCharacters(in: .whitespaces).isEmpty ? "Name" : base.trimmingCharacters(in: .whitespaces)
        let shown = (0..<min(count, 3)).map { "\(name) \(start + $0)" }
        return shown.joined(separator: " · ") + (count > 3 ? " · … \(name) \(start + count - 1)" : "")
    }

    private func apply() { store.batchRename(targets, base: base, start: start) }
    private func close() { store.pendingBatchRename = nil }
}
