import AppKit
import ApplicationServices
import AVFoundation
import Speech
import SwiftUI

/// Dictation from anywhere (⌃⌥⇧D, again to stop): what you say shows in the island as you say it, on this Mac where
/// it can, and goes into the clipboard, and is typed where you were, unless that's turned off.
final class Dictation {
    static let shared = Dictation()
    private static let activityID = "isola.dictation"

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var heard = ""
    private var startedAt = Date()
    private var limit: DispatchWorkItem?
    private(set) var listening = false

    func toggle() {
        listening ? stop() : start()
    }

    private func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.banner("Isola can't hear you yet", "Allow Speech Recognition in System Settings, Privacy & Security")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        granted ? self.begin() : self.banner("Isola can't use the microphone",
                                                             "Allow it in System Settings, Privacy & Security")
                    }
                }
            }
        }
    }

    private func begin() {
        guard !listening, let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            banner("Dictation isn't available", "Speech recognition isn't ready on this Mac")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = true
        self.request = request
        heard = ""
        startedAt = Date()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            banner("Couldn't start listening", error.localizedDescription)
            return
        }
        listening = true
        show()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.heard = result.bestTranscription.formattedString
                    self.show()
                    if result.isFinal { self.finish() }
                }
                if error != nil, self.listening { self.finish() }
            }
        }
        // A minute at most, as macOS's own dictation.
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        limit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    private func show() {
        var activity = LiveActivity(id: Self.activityID, symbol: "waveform", tint: .pink,
                                    title: heard.isEmpty ? "Listening…" : "Dictating")
        activity.subtitle = "⌃⌥⇧D again to stop"
        activity.since = startedAt
        activity.mic = heard.isEmpty ? .listening : .talking
        activity.priority = 4
        if !heard.isEmpty { activity.lines = [LiveActivity.Line(speaker: "You", text: heard)] }
        AppState.shared.setActivity(activity, peek: true)
    }

    /// Stops listening; what was heard so far is used once the last of it is recognised.
    private func stop() {
        guard listening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // a moment for the last words, then done either way
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.finish() }
    }

    private func finish() {
        guard listening else { return }
        listening = false
        limit?.cancel()
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
        AppState.shared.endActivity(Self.activityID)
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if UserDefaults.standard.bool(forKey: Prefs.dictatePastes) && AXIsProcessTrusted() {
            Self.paste()
        } else {
            banner("Copied what you said", text, tint: .green, symbol: "waveform")
        }
    }

    /// ⌘V, to the app you were in.
    private static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(9)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func banner(_ title: String, _ subtitle: String, tint: Color = .orange, symbol: String = "mic.slash.fill") {
        AppState.shared.showBanner(IslandBanner(symbol: symbol, tint: tint, title: title, subtitle: subtitle), for: 3.5)
    }
}
