import CoreAudio
import Foundation

/// Which apps are sending sound to an output right now, from CoreAudio's process objects (macOS 14.2 and later).
/// On older systems the answer is always empty.
enum AudioActivity {
    // CoreAudio selectors, spelled out so Isola builds with SDKs older than 14.2:
    // kAudioHardwarePropertyProcessObjectList, kAudioProcessPropertyBundleID, kAudioProcessPropertyIsRunningOutput.
    private static let processList = code("prs#")
    private static let bundleID = code("pbid")
    private static let runningOutput = code("piro")

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func playingBundleIDs() -> Set<String> {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var list = address(processList)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &list, 0, nil, &size) == noErr, size > 0 else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &list, 0, nil, &size, &processes) == noErr else { return [] }

        var playing: Set<String> = []
        for process in processes {
            var running = UInt32(0)
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = address(runningOutput)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { continue }
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = address(bundleID)
            guard AudioObjectGetPropertyData(process, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let name else { continue }
            playing.insert(name.takeRetainedValue() as String)
        }
        return playing
    }

    /// True when the app with BUNDLE, or one of its helper processes, is playing sound.
    static func isPlaying(_ bundle: String, in playing: Set<String>) -> Bool {
        playing.contains { $0 == bundle || $0.hasPrefix(bundle + ".") }
    }
}
