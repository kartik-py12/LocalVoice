import AppKit
import SwiftUI

@main
struct LocalVoiceApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("LocalVoice", id: "main") {
            AppPanel()
                .environmentObject(state)
        }
        .defaultSize(width: 440, height: 660)
        .windowResizability(.contentSize)

        MenuBarExtra {
            AppPanel()
                .environmentObject(state)
        } label: {
            Image(systemName: state.isRecording ? "waveform" : "waveform.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(state.isRecording ? .red : .primary, .secondary)
        }
        .menuBarExtraStyle(.window)
    }
}
