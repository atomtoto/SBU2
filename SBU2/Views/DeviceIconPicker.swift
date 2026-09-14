//
//  DeviceIconPicker.swift
//  SBU2
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Chooses what a device shows for itself in the list.
///
/// Three kinds of icon, behind two tabs: the system's own symbols, which take the
/// accent colour and sit properly alongside the rest of the interface, and anything
/// the emoji keyboard will give — Genmoji included, since iOS hands those over as
/// images and there is no reason a pack cannot wear one.
struct DeviceIconPicker: View {
    let deviceName: String
    /// What the device would show if nothing were chosen, so "Use default" has
    /// something to put back and to preview.
    let defaultIcon: DeviceIcon
    /// `nil` puts the device back on its default.
    let onPick: (DeviceIcon?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft: DeviceIcon?
    @State private var kind: Kind = .symbols

    init(deviceName: String,
         current: DeviceIcon?,
         defaultIcon: DeviceIcon,
         onPick: @escaping (DeviceIcon?) -> Void) {
        self.deviceName = deviceName
        self.defaultIcon = defaultIcon
        self.onPick = onPick
        _draft = State(initialValue: current)
    }

    private enum Kind: String, CaseIterable, Identifiable {
        case symbols, emoji

        var id: Self { self }

        var label: String {
            switch self {
            case .symbols: return "Symbols"
            case .emoji: return "Emoji"
            }
        }
    }

    private var resolved: DeviceIcon { draft ?? defaultIcon }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                picker
                Divider()
                ScrollView {
                    switch kind {
                    case .symbols: symbolCatalogue
                    case .emoji: emojiCatalogue
                    }
                }
            }
            .navigationTitle("Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onPick(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - What it will look like

    private var preview: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                DeviceIconView(icon: resolved, size: 46)
            }
            .frame(width: 92, height: 92)
            .animation(.snappy(duration: 0.25), value: resolved)

            Text(deviceName)
                .font(.headline)
                .lineLimit(1)

            // Only worth offering once there is something to undo.
            Button("Use default") { draft = nil }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .opacity(draft == nil ? 0 : 1)
                .disabled(draft == nil)
                .animation(.easeInOut(duration: 0.2), value: draft == nil)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    private var picker: some View {
        Picker("Kind", selection: $kind) {
            ForEach(Kind.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    // MARK: - System symbols

    private var symbolCatalogue: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 10)], spacing: 10) {
            ForEach(SymbolCatalogue.groups) { group in
                Section {
                    ForEach(group.symbols, id: \.self) { name in
                        cell(isSelected: resolved == .symbol(name)) {
                            draft = .symbol(name)
                        } content: {
                            Image(systemName: name)
                                .font(.system(size: 24))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
        .padding()
    }

    // MARK: - Emoji and Genmoji

    private var emojiCatalogue: some View {
        VStack(alignment: .leading, spacing: 14) {
            #if canImport(UIKit)
            VStack(alignment: .leading, spacing: 6) {
                Text("Type or draw one")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                GlyphField { picked in
                    draft = picked
                }
                .frame(height: 54)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                Text("Anything the emoji keyboard offers, including a Genmoji you describe yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Text("Or pick one")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 10)], spacing: 10) {
                ForEach(Self.quickEmoji, id: \.self) { emoji in
                    cell(isSelected: resolved == .emoji(emoji)) {
                        draft = .emoji(emoji)
                    } content: {
                        Text(emoji).font(.system(size: 28))
                    }
                }
            }
        }
        .padding()
    }

    /// A spread wide enough to cover what people actually put these packs in,
    /// without turning into a second emoji keyboard.
    private static let quickEmoji = [
        "🔋", "⚡️", "🔌", "🪫", "☀️", "🌙", "🔥", "❄️",
        "🚐", "🚗", "🛻", "🚜", "🏍️", "🛵", "🚲", "🛺",
        "⛵️", "🚤", "🛶", "🏕️", "⛺️", "🏠", "🏝️", "🌊",
        "🧰", "🔧", "📦", "⭐️", "❤️", "🐢", "🦊", "🐻"
    ]

    // MARK: - One tappable tile

    private func cell<Content: View>(isSelected: Bool,
                                     action: @escaping () -> Void,
                                     @ViewBuilder content: () -> Content) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            content()
                .frame(width: 62, height: 62)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

// MARK: - The symbols on offer

private enum SymbolCatalogue {
    struct Group: Identifiable {
        var title: String
        var symbols: [String]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Power", symbols: [
            "bolt.fill", "battery.100", "battery.50", "minus.plus.batteryblock.fill",
            "powerplug.fill", "bolt.batteryblock.fill", "bolt.car.fill", "bolt.horizontal.fill"
        ]),
        Group(title: "Vehicles", symbols: [
            "car.fill", "bus.fill", "truck.box.fill", "tram.fill",
            "bicycle", "scooter", "airplane", "ferry.fill"
        ]),
        Group(title: "On the water", symbols: [
            "sailboat.fill", "water.waves", "fish.fill", "lifepreserver.fill"
        ]),
        Group(title: "Off grid", symbols: [
            "house.fill", "building.2.fill", "tent.fill", "sun.max.fill",
            "wind", "leaf.fill", "mountain.2.fill", "backpack.fill"
        ]),
        Group(title: "Anything else", symbols: [
            "shippingbox.fill", "wrench.and.screwdriver.fill", "gearshape.fill",
            "antenna.radiowaves.left.and.right", "dot.radiowaves.left.and.right",
            "wand.and.sparkles", "star.fill", "heart.fill"
        ])
    ]
}

// MARK: - Catching whatever the keyboard gives

#if canImport(UIKit)
/// A field whose only job is to report the first thing typed into it and then empty
/// itself again.
///
/// A Genmoji is not a character: iOS delivers it as an `NSAdaptiveImageGlyph`
/// attribute on the attributed text, with an object-replacement character standing
/// in for it in the plain string. So the attributed text has to be searched for the
/// glyph, and its image data kept — reading `text` would only ever find the
/// placeholder.
private struct GlyphField: UIViewRepresentable {
    var onPick: (DeviceIcon) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = Coordinator.font
        view.textAlignment = .center
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        if #available(iOS 18.0, *) {
            view.supportsAdaptiveImageGlyph = true
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onPick = onPick
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UITextViewDelegate {
        static let font = UIFont.systemFont(ofSize: 30)

        var onPick: (DeviceIcon) -> Void

        init(onPick: @escaping (DeviceIcon) -> Void) {
            self.onPick = onPick
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let icon = Self.icon(in: textView.attributedText) else { return }
            onPick(icon)
            // Emptied again so the next pick is read on its own rather than appended
            // to the last one. Through `attributedText`, since a Genmoji is not text
            // and would survive clearing `text`.
            textView.attributedText = NSAttributedString(string: "", attributes: [.font: Self.font])
        }

        static func icon(in attributed: NSAttributedString?) -> DeviceIcon? {
            guard let attributed, attributed.length > 0 else { return nil }

            if #available(iOS 18.0, *) {
                var content: Data?
                attributed.enumerateAttribute(.adaptiveImageGlyph,
                                              in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
                    if let glyph = value as? NSAdaptiveImageGlyph {
                        content = glyph.imageContent
                        stop.pointee = true
                    }
                }
                if let content { return .glyph(content) }
            }

            // The last grapheme rather than the last unicode scalar, so a flag or a
            // family arrives whole instead of as its final component.
            guard let last = attributed.string.last, !last.isWhitespace else { return nil }
            return .emoji(String(last))
        }
    }
}
#endif
