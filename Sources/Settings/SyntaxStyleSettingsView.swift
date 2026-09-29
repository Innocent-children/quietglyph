import SwiftUI

struct SyntaxStyleSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var language = "*"
    @State private var role = "default"
    private var style: SyntaxStyle { settings.values.syntaxStyles[language]?[role] ?? SyntaxStyle() }
    private func update(_ body: (inout SyntaxStyle) -> Void) {
        var value = style; body(&value)
        settings.values.syntaxStyles[language, default: [:]][role] = value
    }
    private func text(_ key: WritableKeyPath<SyntaxStyle, String?>) -> Binding<String> {
        Binding(get: { style[keyPath: key] ?? "" }, set: { input in update { $0[keyPath: key] = input.isEmpty ? nil : input } })
    }
    private func flag(_ key: WritableKeyPath<SyntaxStyle, Bool?>) -> Binding<Int> {
        Binding(get: { style[keyPath: key].map { $0 ? 1 : 0 } ?? -1 }, set: { value in update { $0[keyPath: key] = value == -1 ? nil : value == 1 } })
    }
    private func color(_ key: WritableKeyPath<SyntaxStyle, String?>) -> Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(hex: style[keyPath: key]) ?? .textColor) }, set: { input in
            if let value = NSColor(input).usingColorSpace(.sRGB) { update { $0[keyPath: key] = String(format: "#%02X%02X%02X", Int(value.redComponent * 255), Int(value.greenComponent * 255), Int(value.blueComponent * 255)) } }
        })
    }
    var body: some View {
        Form {
            Picker(L10n.text("Language"), selection: $language) {
                Text(L10n.text("Global")).tag("*")
                ForEach(LanguageRegistry.shared.languages) { Text($0.name).tag($0.id) }
            }
            Picker(L10n.text("Syntax Style"), selection: $role) {
                Text(L10n.text("Default")).tag("default")
                ForEach(TokenRole.allCases, id: \.self) { Text(L10n.text($0.rawValue.capitalized)).tag($0.rawValue) }
            }
            Text(L10n.text("Empty values inherit the global style and editor settings.")).font(.caption)
            HStack { TextField(L10n.text("Foreground"), text: text(\.foreground)); ColorPicker("", selection: color(\.foreground), supportsOpacity: false).accessibilityLabel(L10n.text("Foreground")) }
            HStack { TextField(L10n.text("Background"), text: text(\.background)); ColorPicker("", selection: color(\.background), supportsOpacity: false).accessibilityLabel(L10n.text("Background")) }
            TextField(L10n.text("Font"), text: text(\.fontName))
            TextField(L10n.text("Font Size"), text: Binding(get: { style.fontSize.map(String.init(describing:)) ?? "" }, set: { value in update { $0.fontSize = Double(value) } }))
            Picker(L10n.text("Bold"), selection: flag(\.bold)) { Text(L10n.text("Inherit")).tag(-1); Text(L10n.text("Off")).tag(0); Text(L10n.text("On")).tag(1) }
            Picker(L10n.text("Italic"), selection: flag(\.italic)) { Text(L10n.text("Inherit")).tag(-1); Text(L10n.text("Off")).tag(0); Text(L10n.text("On")).tag(1) }
            Picker(L10n.text("Underline"), selection: flag(\.underline)) { Text(L10n.text("Inherit")).tag(-1); Text(L10n.text("Off")).tag(0); Text(L10n.text("On")).tag(1) }
            Button(L10n.text("Reset to Inherited Style")) { settings.values.syntaxStyles[language]?[role] = nil }
        }.formStyle(.grouped)
    }
}
