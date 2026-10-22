import AppKit
import SwiftUI

struct TrayItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

final class FileTray: ObservableObject {
    @Published private(set) var items: [TrayItem] = []
    @Published var statusMessage: String?

    func add(_ urls: [URL]) {
        withAnimation(.easeInOut(duration: 0.2)) {
            for url in urls where !items.contains(where: { $0.url == url }) {
                items.append(TrayItem(url: url))
            }
        }
    }

    func remove(_ item: TrayItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            items.removeAll { $0.id == item.id }
        }
    }

    func clear() {
        withAnimation(.easeInOut(duration: 0.2)) { items.removeAll() }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        FileActions.loadFileURLs(providers) { [weak self] urls in self?.add(urls) }
    }

    func zipAll() {
        FileActions.zip(items.map(\.url)) { [weak self] archive in
            if let archive {
                NSWorkspace.shared.activateFileViewerSelecting([archive])
                self?.flash("Saved \(archive.lastPathComponent) to Downloads")
            } else {
                self?.flash("Could not create the zip")
            }
        }
    }

    func convert(_ item: TrayItem) {
        FileActions.convertImages([item.url]) { [weak self] made in
            guard let self else { return }
            if made.isEmpty {
                self.flash("Could not convert \(item.name)")
            } else {
                self.add(made)
                self.flash("Saved \(made[0].lastPathComponent) to Downloads")
            }
        }
    }

    private func flash(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }
}
