import AppKit
import SwiftUI

private final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RecordingHUDController {
    private var panel: RecordingHUDPanel?

    func show(state: AppState, onStop: (() -> Void)?) {
        let view = RecordingHUDView(
            isRecording: state.isRecording,
            isTranscribing: state.isTranscribing,
            duration: state.recordingDuration,
            level: state.audioLevel,
            message: state.hudMessage,
            onStop: onStop
        )
        if let panel, let host = panel.contentView as? NSHostingView<RecordingHUDView> {
            host.rootView = view
        } else {
            let window = RecordingHUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 78),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isFloatingPanel = true
            window.level = .statusBar
            window.hasShadow = false
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: view)
            panel = window
        }

        guard let panel else { return }
        if !panel.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 10))
            }
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct RecordingHUDView: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let duration: TimeInterval
    let level: Double
    let message: String
    let onStop: (() -> Void)?
    private let barHeights: [CGFloat] = [8, 14, 22, 12, 19, 9, 24, 13, 7]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isRecording ? "waveform" : isTranscribing ? "ellipsis" : "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isRecording ? .red : .accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(message).font(.system(size: 13, weight: .semibold))
                if isRecording {
                    Text("\(formatDuration(duration)) · recording")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if isTranscribing {
                    Text("Your audio stays saved on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Recording saved locally")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            if isRecording {
                HStack(spacing: 3) {
                    ForEach(barHeights.indices, id: \.self) { index in
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 3, height: barHeights[index] * max(0.22, level))
                    }
                }
                .animation(.easeOut(duration: 0.1), value: level)
                if let onStop {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.red, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop recording and transcribe")
                    .help("Stop recording and transcribe")
                }
            } else if isTranscribing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 15)
        .frame(width: 350, height: 78)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.10)))
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}
