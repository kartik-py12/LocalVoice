import Foundation

struct HistoryItem: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var audioFilename: String
    var transcript: String
    var state: String
    var errorMessage: String?
    var duration: TimeInterval?

    var audioURL: URL { AppState.recordingsDirectory.appendingPathComponent(audioFilename) }
}
