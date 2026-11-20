import AppKit
import SwiftUI

/// The island's Tools tab: Isola's tools as tiles, each with its shortcut, for when you don't remember the keys.
struct ToolsView: View {
    @EnvironmentObject var state: AppState

    private struct Tool: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let colors: [Color]
        let keys: String
        let perform: () -> Void
    }

    private var tools: [Tool] {
        [
            Tool(id: "capture", title: "Capture", symbol: "camera.viewfinder",
                 colors: [Color(red: 0.35, green: 0.65, blue: 1), Color(red: 0.15, green: 0.4, blue: 0.95)],
                 keys: Shortcuts.Action.capture.label) { close { Capture.markup() } },
            Tool(id: "text", title: "Copy Text", symbol: "text.viewfinder",
                 colors: [Color(red: 0.3, green: 0.85, blue: 0.8), Color(red: 0.1, green: 0.55, blue: 0.6)],
                 keys: Shortcuts.Action.captureText.label) { close { Capture.text() } },
            Tool(id: "dictate", title: "Dictate", symbol: "waveform",
                 colors: [Color(red: 1, green: 0.4, blue: 0.6), Color(red: 0.85, green: 0.2, blue: 0.45)],
                 keys: Shortcuts.Action.dictate.label) { close { Dictation.shared.toggle() } },
            Tool(id: "colour", title: "Pick Colour", symbol: "eyedropper",
                 colors: [Color(red: 1, green: 0.7, blue: 0.25), Color(red: 0.95, green: 0.45, blue: 0.1)],
                 keys: "") { close { RingMenu.pickColour() } },
            Tool(id: "left", title: "Left Half", symbol: "rectangle.lefthalf.filled",
                 colors: [Color(red: 0.65, green: 0.45, blue: 1), Color(red: 0.45, green: 0.25, blue: 0.85)],
                 keys: Shortcuts.Action.snapLeft.label) { close { WindowSnap.snap(.left) } },
            Tool(id: "right", title: "Right Half", symbol: "rectangle.righthalf.filled",
                 colors: [Color(red: 0.65, green: 0.45, blue: 1), Color(red: 0.45, green: 0.25, blue: 0.85)],
                 keys: Shortcuts.Action.snapRight.label) { close { WindowSnap.snap(.right) } },
            Tool(id: "fill", title: "Fill Screen", symbol: "rectangle.inset.filled",
                 colors: [Color(red: 0.65, green: 0.45, blue: 1), Color(red: 0.45, green: 0.25, blue: 0.85)],
                 keys: Shortcuts.Action.maximize.label) { close { WindowSnap.snap(.maximize) } },
            Tool(id: "mute", title: "Mute Mic", symbol: "mic.slash.fill",
                 colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.85, green: 0.2, blue: 0.2)],
                 keys: Shortcuts.Action.mute.label) { CallControls.shared.toggleMute() },
        ]
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(tools) { tool in
                ToolTile(title: tool.title, symbol: tool.symbol, colors: tool.colors, keys: tool.keys,
                         action: tool.perform)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Closes the island first, so it isn't in the way (or in the picture), then does it.
    private func close(_ then: @escaping () -> Void) {
        state.isExpanded = false
        state.heldOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: then)
    }
}

private struct ToolTile: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let keys: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.white))
                    .shadow(color: colors.last?.opacity(0.45) ?? .clear, radius: hovering ? 8 : 3, y: 2)
                Text(title).font(.system(size: 11.5, weight: .semibold))
                Text(keys.isEmpty ? " " : keys)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.13 : 0.06)))
            .scaleEffect(hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
