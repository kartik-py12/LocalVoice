@main
enum RecordingStartGateTests {
    static func main() {
        precondition(RecordingStartGate.canStart(isStarting: false, isRecording: false, isTranscribing: false))
        precondition(!RecordingStartGate.canStart(isStarting: true, isRecording: false, isTranscribing: false), "A duplicate Fn event must not start a second recorder.")
        precondition(!RecordingStartGate.canStart(isStarting: false, isRecording: true, isTranscribing: false), "Fn must not start another recorder while recording.")
        precondition(!RecordingStartGate.canStart(isStarting: false, isRecording: false, isTranscribing: true), "Fn must not start a new recording while transcription is pending.")
    }
}
