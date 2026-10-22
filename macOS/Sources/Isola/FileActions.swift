import AppKit
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// What the File Tray and the Basket can do with files: AirDrop, convert images, zip.
enum FileActions {
    static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// File URLs from a drop, delivered on the main queue once all have loaded.
    static func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in files {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
        return true
    }

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// JPEGs become PNGs, and so do SVGs, whose transparency would be lost in a JPEG. Every other image becomes a
    /// JPEG.
    static func conversionTarget(for url: URL) -> UTType {
        let type = UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .jpeg) == true || type?.conforms(to: .svg) == true ? .png : .jpeg
    }

    /// Converts the images among URLS into Downloads, off the main thread. Hands back the new files.
    static func convertImages(_ urls: [URL], completion: @escaping ([URL]) -> Void) {
        let images = urls.filter(isImage)
        DispatchQueue.global(qos: .userInitiated).async {
            var made: [URL] = []
            for url in images {
                let target = conversionTarget(for: url)
                guard let decoded = decode(url) else { continue }
                let image = target == .jpeg ? (flattened(decoded) ?? decoded) : decoded
                let output = uniqueURL(
                    in: downloads, base: url.deletingPathExtension().lastPathComponent,
                    extension: target.preferredFilenameExtension ?? "jpg")
                guard let destination = CGImageDestinationCreateWithURL(
                    output as CFURL, target.identifier as CFString, 1, nil) else { continue }
                let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
                CGImageDestinationAddImage(destination, image, target == .jpeg ? options : nil)
                if CGImageDestinationFinalize(destination) { made.append(output) }
            }
            DispatchQueue.main.async { completion(made) }
        }
    }

    /// ImageIO reads most images but not SVG. Those are drawn by NSImage, or failing that by QuickLook, the way Finder
    /// draws its previews, at up to 2048 pixels on the long side.
    private static func decode(_ url: URL) -> CGImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        if let picture = NSImage(contentsOf: url), picture.size.width > 0, picture.size.height > 0 {
            let scale = 2048 / max(picture.size.width, picture.size.height)
            var rect = CGRect(x: 0, y: 0, width: picture.size.width * scale, height: picture.size.height * scale)
            if let image = picture.cgImage(forProposedRect: &rect, context: nil, hints: nil) { return image }
        }
        return renderWithQuickLook(url)
    }

    /// Waits for QuickLook, so it must not be called on the main thread.
    private static func renderWithQuickLook(_ url: URL) -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 2048, height: 2048), scale: 1, representationTypes: .thumbnail)
        let done = DispatchSemaphore(value: 0)
        var result: CGImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
            result = thumbnail?.cgImage
            done.signal()
        }
        _ = done.wait(timeout: .now() + 15)
        return result
    }

    /// JPEG has no transparency: lay the image on white rather than let transparent areas turn black.
    private static func flattened(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// Zips URLS into Downloads without moving or copying them (the archive is built from symbolic links).
    static func zip(_ urls: [URL], completion: @escaping (URL?) -> Void) {
        guard !urls.isEmpty else {
            completion(nil)
            return
        }
        let archive = uniqueURL(in: downloads, base: "Isola-\(Int(Date().timeIntervalSince1970))", extension: "zip")

        DispatchQueue.global(qos: .userInitiated).async {
            let manager = FileManager.default
            let staging = manager.temporaryDirectory.appendingPathComponent("isola-zip-\(UUID().uuidString)")
            var ok = false
            do {
                try manager.createDirectory(at: staging, withIntermediateDirectories: true)
                for url in urls {
                    var name = url.lastPathComponent
                    var n = 1
                    while manager.fileExists(atPath: staging.appendingPathComponent(name).path) {
                        n += 1
                        name = "\(n)-\(url.lastPathComponent)"
                    }
                    try manager.createSymbolicLink(at: staging.appendingPathComponent(name), withDestinationURL: url)
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.currentDirectoryURL = staging
                process.arguments = ["-r", "-q", archive.path, "."]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                ok = process.terminationStatus == 0
            } catch {
                ok = false
            }
            try? manager.removeItem(at: staging)
            DispatchQueue.main.async { completion(ok ? archive : nil) }
        }
    }

    private static func uniqueURL(in folder: URL, base: String, extension ext: String) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
