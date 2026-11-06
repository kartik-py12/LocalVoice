enum RecordingStartGate {
    static func canStart(isStarting: Bool, isRecording: Bool, isTranscribing: Bool) -> Bool {
        !isStarting && !isRecording && !isTranscribing
    }
}
