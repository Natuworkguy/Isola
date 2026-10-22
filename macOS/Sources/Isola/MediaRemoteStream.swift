import Foundation

struct MediaInfo {
    var bundleID: String
    var title: String
    var artist: String
    var isPlaying: Bool
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var artworkData: Data?
}

final class MediaRemoteStream {
    var onInfo: ((MediaInfo?) -> Void)?
    var onFailure: (() -> Void)?

    private let script: URL
    private let framework: URL
    private let testClient: URL
    private let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private let queue = DispatchQueue(label: "isola.mediaremote")
    private var process: Process?
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private var artworkText = ""
    private var artworkBytes: Data?
    private var stopping = false

    init?() {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let directory = resources.appendingPathComponent("Adapter")
        script = directory.appendingPathComponent("mediaremote-adapter.pl")
        framework = directory.appendingPathComponent("MediaRemoteAdapter.framework")
        testClient = directory.appendingPathComponent("MediaRemoteAdapterTestClient")
        let binary = framework.appendingPathComponent("MediaRemoteAdapter")
        let manager = FileManager.default
        guard manager.fileExists(atPath: script.path), manager.fileExists(atPath: binary.path) else { return nil }
    }

    func selfTest(_ completion: @escaping (Bool) -> Void) {
        guard FileManager.default.fileExists(atPath: testClient.path) else {
            completion(false)
            return
        }
        queue.async { [self] in
            let process = Process()
            process.executableURL = perl
            process.arguments = [script.path, framework.path, testClient.path, "test"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var passed = false
            do {
                try process.run()
                process.waitUntilExit()
                passed = process.terminationStatus == 0
            } catch {
                passed = false
            }
            DispatchQueue.main.async { completion(passed) }
        }
    }

    func start() {
        stopping = false
        let process = Process()
        process.executableURL = perl
        process.arguments = [script.path, framework.path, "stream", "--micros", "--debounce=80"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.stopping else { return }
                self.onFailure?()
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            onFailure?()
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
    }

    func send(_ command: Int) {
        run(["send", String(command)])
    }

    func seek(micros: Int) {
        run(["seek", String(micros)])
    }

    private func run(_ arguments: [String]) {
        queue.async { [self] in
            let process = Process()
            process.executableURL = perl
            process.arguments = [script.path, framework.path] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            merge(payload, isDiff: (object["diff"] as? Bool) ?? false)
        }
    }

    private func merge(_ payload: [String: Any], isDiff: Bool) {
        if isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    state.removeValue(forKey: key)
                } else {
                    state[key] = value
                }
            }
        } else {
            state = payload.filter { !($0.value is NSNull) }
        }
        let info = makeInfo()
        DispatchQueue.main.async { [weak self] in self?.onInfo?(info) }
    }

    private func number(_ key: String) -> Double? {
        (state[key] as? NSNumber)?.doubleValue
    }

    private func makeInfo() -> MediaInfo? {
        guard let bundleID = state["bundleIdentifier"] as? String,
              let title = state["title"] as? String else { return nil }

        var artwork: Data?
        if let text = state["artworkData"] as? String {
            if text != artworkText {
                artworkText = text
                artworkBytes = Data(base64Encoded: text, options: .ignoreUnknownCharacters)
            }
            artwork = artworkBytes
        } else {
            artworkText = ""
            artworkBytes = nil
        }

        let stamp = (number("timestampEpochMicros") ?? Date().timeIntervalSince1970 * 1_000_000) / 1_000_000
        return MediaInfo(
            bundleID: (state["parentApplicationBundleIdentifier"] as? String) ?? bundleID,
            title: title,
            artist: (state["artist"] as? String) ?? "",
            isPlaying: (state["playing"] as? Bool) ?? false,
            duration: (number("durationMicros") ?? 0) / 1_000_000,
            elapsed: (number("elapsedTimeMicros") ?? 0) / 1_000_000,
            timestamp: Date(timeIntervalSince1970: stamp),
            rate: number("playbackRate") ?? 1,
            artworkData: artwork
        )
    }
}
