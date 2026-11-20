import AppKit
import SwiftUI

/// Folders Isola keeps an eye on: a file that appears in one (a download finishing, a screenshot, an export) goes
/// straight into the File Tray, with a banner saying where it came from. Chosen in Settings, under File Tray.
final class WatchedFolders: ObservableObject {
    static let shared = WatchedFolders()

    @Published private(set) var folders: [URL] = []
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var known: [URL: Set<String>] = [:]

    private init() {}

    func start() {
        folders = Self.saved()
        restart()
    }

    func add(_ folder: URL) {
        guard !folders.contains(folder) else { return }
        folders.append(folder)
        save()
        restart()
    }

    func remove(_ folder: URL) {
        folders.removeAll { $0 == folder }
        save()
        restart()
    }

    /// Asks for a folder to watch.
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        panel.message = "New files in these folders go into Isola's File Tray."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { panel.urls.forEach(add) }
    }

    private static func saved() -> [URL] {
        (UserDefaults.standard.string(forKey: Prefs.watchedFolders) ?? "")
            .split(separator: "\n").map { URL(fileURLWithPath: String($0), isDirectory: true) }
    }

    private func save() {
        UserDefaults.standard.set(folders.map(\.path).joined(separator: "\n"), forKey: Prefs.watchedFolders)
    }

    private func restart() {
        sources.values.forEach { $0.cancel() }
        sources = [:]
        known = [:]
        for folder in folders {
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            known[folder] = Set(names(in: folder))
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in self?.changed(folder) }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources[folder] = source
        }
    }

    private func names(in folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    /// Something changed in FOLDER: what's new and finished goes to the tray. A file still being written (a download
    /// in progress, a hidden temporary file) waits until it's done; the folder changes again when it is.
    private func changed(_ folder: URL) {
        // a moment's grace, so a file being moved in has finished arriving
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, var seen = self.known[folder] else { return }
            let now = Set(self.names(in: folder))
            let partial = ["download", "crdownload", "part", "partial", "tmp"]
            let fresh = now.subtracting(seen).filter { name in
                !name.hasPrefix(".") && !partial.contains((name as NSString).pathExtension.lowercased())
            }
            seen = seen.intersection(now).union(fresh)
            self.known[folder] = seen
            guard !fresh.isEmpty else { return }
            let urls = fresh.sorted().map { folder.appendingPathComponent($0) }
            let state = AppState.shared
            state.tray.add(urls)
            state.showBanner(IslandBanner(
                symbol: "tray.and.arrow.down.fill", tint: .blue,
                title: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) new files",
                subtitle: "From \(folder.lastPathComponent), in the tray"), for: 3)
        }
    }
}
