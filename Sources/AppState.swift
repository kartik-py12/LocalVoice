import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation

private enum PasteAttempt {
    case sent(String)
    case disabled
    case permissionMissing
    case localVoiceFocused
    case focusChanged
    case eventCreationFailed
}

@MainActor
final class AppState: ObservableObject {
    nonisolated static let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LocalVoice", isDirectory: true)
    nonisolated static let recordingsDirectory = supportDirectory.appendingPathComponent("Recordings", isDirectory: true)
    nonisolated static let historyURL = supportDirectory.appendingPathComponent("history.json")
    nonisolated static let environmentFile = supportDirectory.appendingPathComponent("LocalVoice.env")

    @Published private(set) var entries: [HistoryItem] = []
    @Published private(set) var isStartingRecording = false
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var audioLevel = 0.0
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var hudMessage = "Listening"
    @Published private(set) var apiKeyConfigured = false
    @Published private(set) var apiKeyMessage: String?
    @Published private(set) var billingKeyConfigured = false
    @Published private(set) var billingKeyMessage: String?
    @Published private(set) var functionKeyEnabled = false
    @Published private(set) var functionKeyLastDetectedAt: Date?
    @Published private(set) var autoPasteEnabled = UserDefaults.standard.bool(forKey: "autoPasteEnabled")
    @Published private(set) var statusMessage = "Ready when you are."
    @Published private(set) var isRefreshingBalances = false
    @Published private(set) var deepgramBalances: [DeepgramProjectBalance] = []
    @Published private(set) var balanceMessage: String?
    @Published private(set) var balancesUpdatedAt: Date?

    private var recorder: AVAudioRecorder?
    private var currentRecordingID: UUID?
    private var liveTimer: Timer?
    private var recordingStartedAt: Date?
    private var hudHideTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private let hudController = RecordingHUDController()
    private let functionKeyMonitor = FunctionKeyMonitor()

    var trackedUsageEntries: [HistoryItem] {
        entries.filter { $0.state == "Ready" && $0.duration != nil }
    }
    var trackedUsageSeconds: TimeInterval {
        trackedUsageEntries.compactMap(\.duration).reduce(0, +)
    }
    var trackedMonthEntries: [HistoryItem] {
        trackedUsageEntries.filter { Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }
    }
    var trackedMonthSeconds: TimeInterval {
        trackedMonthEntries.compactMap(\.duration).reduce(0, +)
    }

    init() {
        createStorage()
        loadHistory()
        refreshConfiguration()
        functionKeyMonitor.onPress = { [weak self] in
            guard let self else { return }
            self.functionKeyLastDetectedAt = Date()
            self.toggleRecording()
        }
        refreshFunctionKeyMonitor()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFunctionKeyMonitor() }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }
        guard RecordingStartGate.canStart(isStarting: isStartingRecording, isRecording: isRecording, isTranscribing: isTranscribing) else {
            if isTranscribing { statusMessage = "Transcription is still finishing. Press Fn again when it’s done." }
            return
        }
        isStartingRecording = true
        statusMessage = "Starting recording…"
        Task { await startRecording() }
    }

    func enableFunctionKey() {
        functionKeyEnabled = functionKeyMonitor.start()
        statusMessage = functionKeyEnabled
            ? "Fn listener is active. Press Fn once to confirm it responds."
            : "In Input Monitoring, click +, add LocalVoice.app from ~/Applications, switch it on, then retry Fn."
        if !functionKeyEnabled { openInputMonitoringSettings() }
    }

    func setAutoPasteEnabled(_ enabled: Bool) {
        autoPasteEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "autoPasteEnabled")
        guard enabled else {
            statusMessage = "Auto-paste is off. Transcripts will still be copied."
            return
        }
        statusMessage = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
            ? "Auto-paste is enabled. It sends ⌘V, never Return."
            : "Auto-paste needs LocalVoice enabled in System Settings → Privacy & Security → Accessibility."
    }

    func refreshFunctionKeyMonitor() {
        guard CGPreflightListenEventAccess() else {
            functionKeyEnabled = false
            return
        }
        functionKeyEnabled = functionKeyMonitor.start()
    }

    func openInputMonitoringSettings() {
        let destinations = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ]
        for destination in destinations {
            if let url = URL(string: destination), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        statusMessage = "In System Settings, open Privacy & Security → Input Monitoring and enable LocalVoice."
    }

    @discardableResult
    func saveAPIKey(_ rawValue: String) -> Bool {
        let key = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        do {
            try DeepgramKeychain.save(key)
            apiKeyConfigured = true
            apiKeyMessage = "Key saved securely in macOS Keychain."
            statusMessage = "Deepgram key saved securely."
            return true
        } catch {
            apiKeyMessage = error.localizedDescription
            statusMessage = "Couldn’t save the Deepgram key."
            return false
        }
    }

    @discardableResult
    func saveBillingAPIKey(_ rawValue: String) -> Bool {
        let key = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        do {
            try DeepgramKeychain.saveBilling(key)
            billingKeyConfigured = true
            billingKeyMessage = "Billing key saved securely in macOS Keychain."
            statusMessage = "Deepgram billing key saved securely."
            return true
        } catch {
            billingKeyMessage = error.localizedDescription
            statusMessage = "Couldn’t save the Deepgram billing key."
            return false
        }
    }

    func refreshConfiguration() {
        apiKeyConfigured = deepgramAPIKey != nil
        billingKeyConfigured = DeepgramKeychain.loadBilling() != nil
    }

    func copy(_ item: HistoryItem) {
        guard !item.transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.transcript, forType: .string)
        statusMessage = "Copied to clipboard."
    }

    func revealRecording(_ item: HistoryItem) {
        guard FileManager.default.fileExists(atPath: item.audioURL.path) else {
            statusMessage = "The saved audio file could not be found."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([item.audioURL])
    }

    func refreshDeepgramBalances() {
        guard !isRefreshingBalances else { return }
        guard let apiKey = deepgramBillingAPIKey else {
            balanceMessage = "Add your Deepgram API key in Settings first."
            return
        }
        isRefreshingBalances = true
        balanceMessage = "Refreshing balances from Deepgram…"
        Task {
            defer { isRefreshingBalances = false }
            do {
                deepgramBalances = try await DeepgramClient.fetchBalances(apiKey: apiKey)
                balancesUpdatedAt = Date()
                balanceMessage = deepgramBalances.isEmpty
                    ? "Deepgram returned no outstanding balances for these projects."
                    : "Balances updated from Deepgram."
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("scope") {
                    balanceMessage = "This key lacks billing access. Add a separate key with project:read and billing:read in Settings; Deepgram’s Admin role includes them."
                } else {
                    balanceMessage = message
                }
            }
        }
    }

    func delete(_ item: HistoryItem) {
        guard item.state != "Transcribing" && item.state != "Recording" else { return }
        try? FileManager.default.removeItem(at: item.audioURL)
        entries.removeAll { $0.id == item.id }
        saveHistory()
    }

    func retry(_ item: HistoryItem) {
        guard !isStartingRecording && !isRecording && !isTranscribing else {
            statusMessage = "Finish the current recording or transcription before retrying."
            return
        }
        guard item.state == "Failed", let apiKey = deepgramAPIKey else {
            statusMessage = "Add your Deepgram API key in Settings first."
            return
        }
        update(item.id) { $0.state = "Transcribing"; $0.errorMessage = nil }
        isTranscribing = true
        hudMessage = "Transcribing saved audio"
        hudController.show(state: self, onStop: nil)
        statusMessage = "Transcribing saved audio…"
        Task { await transcribe(itemID: item.id, apiKey: apiKey) }
    }

    func stopForQuit() {
        guard isRecording else { return }
        stopRecording(shouldTranscribe: false)
    }

    private func startRecording() async {
        defer { isStartingRecording = false }
        guard !isRecording && !isTranscribing else { return }
        refreshConfiguration()
        guard deepgramAPIKey != nil else {
            statusMessage = "Add DEEPGRAM_API_KEY in Settings before recording."
            return
        }
        guard await microphoneAccess() else {
            statusMessage = "Allow microphone access for LocalVoice in System Settings."
            return
        }

        let id = UUID()
        let audioURL = Self.recordingsDirectory.appendingPathComponent("\(id.uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder.isMeteringEnabled = true
            audioRecorder.prepareToRecord()
            guard audioRecorder.record() else { throw TranscriptionError.invalidResponse }
            recorder = audioRecorder
            currentRecordingID = id
            recordingStartedAt = Date()
            recordingDuration = 0
            audioLevel = 0
            isTranscribing = false
            isRecording = true
            statusMessage = "Listening… press Fn or Stop when you’re done."
            hudMessage = "Listening"
            entries.insert(HistoryItem(
                id: id,
                createdAt: Date(),
                audioFilename: audioURL.lastPathComponent,
                transcript: "",
                state: "Recording",
                errorMessage: nil,
                duration: nil
            ), at: 0)
            saveHistory()
            playSystemSound("Pop")
            hudHideTask?.cancel()
            hudController.show(state: self, onStop: { [weak self] in self?.toggleRecording() })
            liveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateRecordingHUD() }
            }
        } catch {
            statusMessage = "Couldn’t start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording(shouldTranscribe: Bool = true) {
        guard let recorder, let id = currentRecordingID else { return }
        recordingDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        currentRecordingID = nil
        isRecording = false
        liveTimer?.invalidate()
        liveTimer = nil
        audioLevel = 0
        update(id) { $0.duration = recordingDuration }

        guard let apiKey = deepgramAPIKey else {
            update(id) { $0.state = "Saved" }
            statusMessage = "Recording saved locally. Add your API key to transcribe it."
            hudMessage = "Recording saved"
            isTranscribing = false
            showHUDBriefly()
            return
        }
        guard shouldTranscribe else {
            update(id) { $0.state = "Saved" }
            statusMessage = "Recording saved locally."
            hudController.hide()
            return
        }
        isTranscribing = true
        hudMessage = "Transcribing"
        hudController.show(state: self, onStop: nil)
        update(id) { $0.state = "Transcribing" }
        statusMessage = "Transcribing with Deepgram…"
        Task { await transcribe(itemID: id, apiKey: apiKey) }
    }

    private func transcribe(itemID: UUID, apiKey: String) async {
        guard let item = entries.first(where: { $0.id == itemID }) else { return }
        do {
            let transcript = try await DeepgramClient.transcribe(fileURL: item.audioURL, apiKey: apiKey)
            update(itemID) { $0.transcript = transcript; $0.state = "Ready"; $0.errorMessage = nil }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            let pasteAttempt = autoPasteEnabled ? await pasteTranscript() : .disabled
            switch pasteAttempt {
            case .sent(let appName): statusMessage = "Sent ⌘V to \(appName). Transcript remains on the clipboard."
            case .disabled: statusMessage = "Transcript copied to clipboard."
            case .permissionMissing: statusMessage = "Copied. macOS has not granted LocalVoice permission to post ⌘V. Re-enable Auto-paste in Settings, then allow LocalVoice in Accessibility."
            case .localVoiceFocused: statusMessage = "Copied. Switch to the app and text field you want, then use Fn to dictate."
            case .focusChanged: statusMessage = "Copied. The active app changed; use ⌘V to paste safely."
            case .eventCreationFailed: statusMessage = "Copied. macOS could not create the paste shortcut; use ⌘V."
            }
            isTranscribing = false
            if case .sent = pasteAttempt { hudMessage = "Paste sent — ready" }
            else { hudMessage = "Copied — ready to paste" }
            playSystemSound("Glass")
            showHUDBriefly()
        } catch {
            let message = error.localizedDescription
            update(itemID) { $0.state = "Failed"; $0.errorMessage = message }
            statusMessage = message
            isTranscribing = false
            hudMessage = "Transcription failed"
            showHUDBriefly()
        }
    }

    private func updateRecordingHUD() {
        guard isRecording else { return }
        recorder?.updateMeters()
        let decibels = Double(recorder?.averagePower(forChannel: 0) ?? -60)
        audioLevel = min(1, max(0, (decibels + 55) / 55))
        if let recordingStartedAt { recordingDuration = Date().timeIntervalSince(recordingStartedAt) }
        hudController.show(state: self, onStop: { [weak self] in self?.toggleRecording() })
    }

    private func showHUDBriefly() {
        hudHideTask?.cancel()
        hudController.show(state: self, onStop: nil)
        hudHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hudController.hide()
        }
    }

    private func playSystemSound(_ name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) { sound.play() }
        else { NSSound.beep() }
    }

    private func pasteTranscript() async -> PasteAttempt {
        guard CGPreflightPostEventAccess() else { return .permissionMissing }
        guard let target = NSWorkspace.shared.frontmostApplication else { return .eventCreationFailed }
        guard target.bundleIdentifier != Bundle.main.bundleIdentifier else { return .localVoiceFocused }
        // Let the new pasteboard contents settle, and avoid pasting if focus changes meanwhile.
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return .focusChanged }
        guard
              let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return .eventCreationFailed }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .sent(target.localizedName ?? "the active app")
    }

    private func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default: return false
        }
    }

    private var deepgramAPIKey: String? {
        if let value = DeepgramKeychain.load(), !value.isEmpty { return value }
        if let value = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        guard let contents = try? String(contentsOf: Self.environmentFile, encoding: .utf8) else { return nil }
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "DEEPGRAM_API_KEY" else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2, value.first == "\"", value.last == "\"" { value.removeFirst(); value.removeLast() }
            if value.count >= 2, value.first == "'", value.last == "'" { value.removeFirst(); value.removeLast() }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private var deepgramBillingAPIKey: String? {
        if let value = DeepgramKeychain.loadBilling(), !value.isEmpty { return value }
        return deepgramAPIKey
    }

    private func createStorage() {
        let manager = FileManager.default
        try? manager.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        try? manager.createDirectory(at: Self.recordingsDirectory, withIntermediateDirectories: true)
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.supportDirectory.path)
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.recordingsDirectory.path)
    }

    private func loadHistory() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.historyURL),
              let saved = try? decoder.decode([HistoryItem].self, from: data) else { return }
        entries = saved.sorted { $0.createdAt > $1.createdAt }
        for index in entries.indices where entries[index].state == "Recording" || entries[index].state == "Transcribing" {
            entries[index].state = "Failed"
            entries[index].errorMessage = "This recording was interrupted. Retry transcription from History."
        }
        saveHistory()
    }

    private func update(_ id: UUID, change: (inout HistoryItem) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        saveHistory()
    }

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: Self.historyURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.historyURL.path)
        } catch {
            statusMessage = "Couldn’t save history: \(error.localizedDescription)"
        }
    }
}
