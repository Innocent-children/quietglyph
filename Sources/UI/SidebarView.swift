import SwiftUI
import AppKit

struct OpenDocumentItem: Identifiable {
    var id: UUID
    var title: String
    var modified: Bool
    var activate: () -> Void
}

final class FolderNode: Identifiable {
    let url: URL
    var id: URL { url }
    private var cached: [FolderNode]?
    init(_ url: URL) { self.url = url }
    var children: [FolderNode]? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
        if cached == nil {
            cached = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.map(FolderNode.init)
        }
        return cached
    }
}

@MainActor
final class SidebarModel: ObservableObject {
    @Published var documents: [OpenDocumentItem] = []
    @Published var folder: [FolderNode] = []
    @Published var bookmarks: [Int] = []
    @Published var selectedTab = 0
    var onOpen: ((URL) -> Void)?
    var onBookmark: ((Int) -> Void)?
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { folder = [FolderNode(url)] }
    }
}

struct SidebarView: View {
    @ObservedObject var model: SidebarModel
    var body: some View {
        VStack(spacing: 0) {
            if model.selectedTab == 1 {
                List(model.bookmarks, id: \.self) { line in
                    Button(L10n.format("Line %ld", line)) { model.onBookmark?(line) }.buttonStyle(.plain)
                }
            } else {
                List {
                    Section(L10n.text("Open Documents")) {
                        ForEach(model.documents) { document in
                            Button { document.activate() } label: {
                                Label(document.title + (document.modified ? " •" : ""), systemImage: "doc.text").lineLimit(1)
                            }.buttonStyle(.plain)
                        }
                    }
                    if !model.folder.isEmpty {
                        Section(L10n.text("Folder")) {
                            OutlineGroup(model.folder, children: \.children) { node in
                                Button { if node.children == nil { model.onOpen?(node.url) } } label: {
                                    Label(node.url.lastPathComponent, systemImage: node.children == nil ? "doc" : "folder")
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.listStyle(.sidebar)
                Button(L10n.text("Open Folder…")) { model.chooseFolder() }.padding(10)
            }
        }.frame(minWidth: 170, idealWidth: 220, maxWidth: 340)
    }
}
