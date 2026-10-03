import AppKit
import Combine

struct KeyBinding: Codable, Equatable {
    var key: String
    var modifiers: UInt
}

struct Preferences: Codable {
    var fontName = "SFMono-Regular"
    var fontSize = 13.0
    var tabWidth = 4
    var useSpaces = true
    var autoIndent = true
    var wrapLines = true
    var showWhitespace = false
    var showLineEndings = false
    var detectLinks = false
    var restoreSession = true
    var reduceMotion = false
    var themeID = "system"
    var shortcuts: [String: KeyBinding] = [:]
    var syntaxStyles: [String: [String: SyntaxStyle]] = [:]
    var highlightCurrentLine = true
    var indentGuides = true
    var highlightOccurrences = true
    var matchBrackets = true
    var timedSave = false
    var rememberWindowFrame = true
    var clearRecentOnQuit = false
    var largeFileThresholdMB = 100
}

struct SyntaxStyle: Codable, Equatable {
    var foreground: String?
    var background: String?
    var fontName: String?
    var fontSize: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
}

struct EditorTheme: Codable, Identifiable {
    var id: String
    var name: String
    var colors: [String: String]
    var foreground: NSColor { NSColor(hex: colors["foreground"]) ?? .textColor }
    var background: NSColor { NSColor(hex: colors["background"]) ?? .textBackgroundColor }
    func color(_ role: TokenRole) -> NSColor {
        if let color = NSColor(hex: colors[role.rawValue]) { return color }
        switch role {
        case .keyword: return .systemPurple
        case .string: return .systemRed
        case .comment: return .secondaryLabelColor
        case .number: return .systemBlue
        case .type: return .systemTeal
        case .heading: return .systemIndigo
        case .added: return .systemGreen
        case .removed: return .systemRed
        }
    }
}

extension NSColor {
    convenience init?(hex: String?) {
        guard let hex, let value = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    nonisolated private static let fileLimitLock = NSLock()
    nonisolated(unsafe) private static var fileLimitBytes: UInt64 = 100 * 1024 * 1024
    nonisolated static var editableLimit: UInt64 { fileLimitLock.withLock { fileLimitBytes } }
    static let shared = SettingsStore()
    static let changed = Notification.Name("InklineSettingsChanged")
    @Published var interfaceLanguage = InterfaceLanguage.saved(in: L10n.defaults) {
        didSet { L10n.defaults.set(interfaceLanguage.rawValue, forKey: InterfaceLanguage.defaultsKey) }
    }
    @Published var values: Preferences {
        didSet {
            Self.fileLimitLock.withLock { Self.fileLimitBytes = UInt64(min(600, max(50, values.largeFileThresholdMB))) * 1024 * 1024 }
            if !InklineApplication.isTesting, let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: "nativePreferences") }
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }
    let themes: [EditorTheme]
    var currentTheme: EditorTheme { themes.first { $0.id == values.themeID } ?? themes[0] }
    var fontName: String { values.fontName }
    var fontSize: CGFloat { CGFloat(min(72, max(8, values.fontSize))) }
    var tabWidth: Int { min(16, max(1, values.tabWidth)) }
    var useSpaces: Bool { values.useSpaces }
    var autoIndent: Bool { values.autoIndent }
    var wrapLines: Bool { values.wrapLines }
    var showWhitespace: Bool { values.showWhitespace || values.showLineEndings }
    var showLineEndings: Bool { values.showLineEndings }
    func syntaxAttributes(language: String, role: TokenRole?) -> [NSAttributedString.Key: Any] {
        let key = role?.rawValue ?? "default"
        let global = values.syntaxStyles["*"]?[key] ?? SyntaxStyle()
        let local = values.syntaxStyles[language]?[key] ?? SyntaxStyle()
        let base = values.syntaxStyles[language]?["default"] ?? SyntaxStyle()
        let globalBase = values.syntaxStyles["*"]?["default"] ?? SyntaxStyle()
        let size = CGFloat(min(72, max(8, local.fontSize ?? global.fontSize ?? base.fontSize ?? globalBase.fontSize ?? values.fontSize)))
        var font = NSFont(name: local.fontName ?? global.fontName ?? base.fontName ?? globalBase.fontName ?? fontName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        if local.bold ?? global.bold ?? false { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if local.italic ?? global.italic ?? false { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        var attributes: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: NSColor(hex: local.foreground ?? global.foreground) ?? role.map { currentTheme.color($0) } ?? currentTheme.foreground,
            .underlineStyle: local.underline ?? global.underline ?? false ? NSUnderlineStyle.single.rawValue : 0]
        attributes[.obliqueness] = (local.italic ?? global.italic ?? false) && !NSFontManager.shared.traits(of: font).contains(.italicFontMask) ? 0.2 : 0
        if let color = NSColor(hex: local.background ?? global.background) { attributes[.backgroundColor] = color }
        return attributes
    }
    init() {
        if !InklineApplication.isTesting, let data = UserDefaults.standard.data(forKey: "nativePreferences"),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) { values = saved }
        else { values = Preferences() }
        var result = [EditorTheme(id: "system", name: "System", colors: [:])]
        for url in Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? [] {
            if let data = try? Data(contentsOf: url), let theme = try? JSONDecoder().decode(EditorTheme.self, from: data) { result.append(theme) }
        }
        themes = result
        Self.fileLimitLock.withLock { Self.fileLimitBytes = UInt64(min(600, max(50, values.largeFileThresholdMB))) * 1024 * 1024 }
    }
}
