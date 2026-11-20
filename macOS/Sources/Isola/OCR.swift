import AppKit
import Vision

/// Reading the text in a picture, on this Mac (Vision), for "Copy text" on images in the tray and the clipboard,
/// and for capturing the text in any part of the screen.
enum OCR {
    /// The text in IMAGE, line by line, top to bottom. Works off the main thread; COMPLETION runs on the main queue.
    static func text(in image: CGImage, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
        }
    }

    static func text(in image: NSImage, completion: @escaping (String) -> Void) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion("")
            return
        }
        text(in: cg, completion: completion)
    }

    static func text(at url: URL, completion: @escaping (String) -> Void) {
        guard let image = NSImage(contentsOf: url) else {
            completion("")
            return
        }
        text(in: image, completion: completion)
    }

    /// Reads IMAGE and puts its text on the clipboard, saying in the island how it went.
    static func copyText(of image: NSImage) {
        text(in: image) { found in
            let state = AppState.shared
            guard !found.isEmpty else {
                state.showBanner(IslandBanner(symbol: "text.viewfinder", tint: .orange, title: "No text found",
                                              subtitle: "There's nothing to read in it."), for: 2.5)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(found, forType: .string)
            let words = found.split(whereSeparator: \.isWhitespace).count
            state.showBanner(IslandBanner(symbol: "text.viewfinder", tint: .green, title: "Copied the text",
                                          subtitle: "\(words) word\(words == 1 ? "" : "s")"), for: 2.5)
        }
    }

    static func copyText(at url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        copyText(of: image)
    }
}
