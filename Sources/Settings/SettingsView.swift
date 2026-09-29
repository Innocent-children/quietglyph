import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    var body: some View {
        TabView {
            Form {
                Section(L10n.text("Application Language")) {
                    Picker(L10n.text("Interface language"), selection: $settings.interfaceLanguage) {
                        ForEach(InterfaceLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
                    }.accessibilityIdentifier("interfaceLanguage")
                    Text(L10n.text("The selected language takes effect the next time you open QuietGlyph."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("Editor")) {
                    TextField(L10n.text("Font"), text: $settings.values.fontName)
                    Stepper(L10n.format("Font size: %ld", Int(settings.values.fontSize)), value: $settings.values.fontSize, in: 8...72)
                    Stepper(L10n.format("Tab width: %ld", settings.values.tabWidth), value: $settings.values.tabWidth, in: 1...16)
                    Toggle(L10n.text("Insert spaces for Tab"), isOn: $settings.values.useSpaces)
                    Toggle(L10n.text("Automatic indentation"), isOn: $settings.values.autoIndent)
                    Toggle(L10n.text("Wrap lines"), isOn: $settings.values.wrapLines)
                    Toggle(L10n.text("Show whitespace"), isOn: $settings.values.showWhitespace)
                    Toggle(L10n.text("Show line endings"), isOn: $settings.values.showLineEndings)
                    Toggle(L10n.text("Detect links"), isOn: $settings.values.detectLinks)
                    Toggle(L10n.text("Highlight Current Line"), isOn: $settings.values.highlightCurrentLine)
                    Toggle(L10n.text("Indent Guides"), isOn: $settings.values.indentGuides)
                    Toggle(L10n.text("Highlight Same Words"), isOn: $settings.values.highlightOccurrences)
                    Toggle(L10n.text("Match Brackets and Tags"), isOn: $settings.values.matchBrackets)
                }
                Section(L10n.text("Appearance & session")) {
                    Picker(L10n.text("Theme"), selection: $settings.values.themeID) {
                        ForEach(settings.themes) { Text(L10n.text($0.name)).tag($0.id) }
                    }
                    Toggle(L10n.text("Reduce animations"), isOn: $settings.values.reduceMotion)
                    Toggle(L10n.text("Restore open files on launch"), isOn: $settings.values.restoreSession)
                    Toggle(L10n.text("Save named files every 3 minutes"), isOn: $settings.values.timedSave)
                    Toggle(L10n.text("Remember window position and size"), isOn: $settings.values.rememberWindowFrame)
                    Toggle(L10n.text("Clear recent files on quit"), isOn: $settings.values.clearRecentOnQuit)
                    Stepper(L10n.format("Large file threshold: %ld MB", settings.values.largeFileThresholdMB), value: $settings.values.largeFileThresholdMB, in: 50...600, step: 10)
                    Text(L10n.text("System Reduce Motion and Reduce Transparency are always respected.")).font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label(L10n.text("General"), systemImage: "gearshape") }
            ShortcutSettingsView().tabItem { Label(L10n.text("Shortcuts"), systemImage: "keyboard") }
            SyntaxStyleSettingsView().tabItem { Label(L10n.text("Syntax Styles"), systemImage: "paintpalette") }
            LanguageDefinitionEditor().tabItem { Label(L10n.text("Languages"), systemImage: "curlybraces") }
        }.padding(12).frame(width: 620, height: 680)
    }
}
