import Foundation

enum DeepgramClient {
    static let nova3MultilingualRatePerMinute = 0.0052

    static func transcribe(fileURL: URL, apiKey: String) async throws -> String {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: "multi"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data).reason)
            throw TranscriptionError.server(message ?? "Deepgram returned HTTP \(http.statusCode).")
        }
        let result = try JSONDecoder().decode(TranscriptResponse.self, from: data)
        let transcript = result.results.channels.first?.alternatives.first?.transcript.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !transcript.isEmpty else { throw TranscriptionError.emptyTranscript }
        return transcript
    }

    static func fetchBalances(apiKey: String) async throws -> [DeepgramProjectBalance] {
        let projectsResponse: ProjectsResponse = try await get("https://api.deepgram.com/v1/projects", apiKey: apiKey)
        var balances: [DeepgramProjectBalance] = []
        for project in projectsResponse.projects ?? [] {
            let url = "https://api.deepgram.com/v1/projects/\(project.projectID)/balances"
            let response: BalancesResponse = try await get(url, apiKey: apiKey)
            balances += (response.balances ?? []).map {
                DeepgramProjectBalance(projectID: project.projectID, projectName: project.name ?? project.projectID, balanceID: $0.balanceID, amount: $0.amount, units: $0.units)
            }
        }
        return balances
    }

    private static func get<T: Decodable>(_ url: String, apiKey: String) async throws -> T {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(APIError.self, from: data)
            throw TranscriptionError.server(payload?.reason ?? "Deepgram returned HTTP \(http.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct DeepgramProjectBalance: Identifiable {
    let projectID: String
    let projectName: String
    let balanceID: String?
    let amount: Double
    let units: String
    var id: String { "\(projectID)-\(balanceID ?? String(amount))" }
}

private struct ProjectsResponse: Decodable {
    struct Project: Decodable {
        let project_id: String
        let name: String?
        var projectID: String { project_id }
    }
    let projects: [Project]?
}

private struct BalancesResponse: Decodable {
    struct Balance: Decodable {
        let balance_id: String?
        let amount: Double
        let units: String
        var balanceID: String? { balance_id }
    }
    let balances: [Balance]?
}

private struct TranscriptResponse: Decodable {
    struct Results: Decodable {
        struct Channel: Decodable {
            struct Alternative: Decodable { let transcript: String }
            let alternatives: [Alternative]
        }
        let channels: [Channel]
    }
    let results: Results
}

private struct APIError: Decodable {
    let err_msg: String?
    let message: String?
    var reason: String? { err_msg ?? message }
}

enum TranscriptionError: LocalizedError {
    case invalidResponse
    case server(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Deepgram returned an invalid response."
        case .server(let message): message
        case .emptyTranscript: "No speech was detected. The recording is still saved locally."
        }
    }
}
