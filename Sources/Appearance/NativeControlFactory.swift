import AppKit

@MainActor
enum NativeControlFactory {
    static func navigation(labels: [String], target: AnyObject?, action: Selector?) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels.map { L10n.text($0) }, trackingMode: .selectOne, target: target, action: action)
        if #available(macOS 27.0, *) { control.role = .tabs }
        control.setAccessibilityLabel(L10n.text("Sidebar"))
        return control
    }
    static func menuItem(title: String, selector: Selector?, key: String = "", target: AnyObject? = nil, localizeTitle: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: localizeTitle ? L10n.text(title) : title, action: selector, keyEquivalent: key)
        item.target = target
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .automatic }
        return item
    }
}
