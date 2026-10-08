import Foundation

struct JevDecisionClient: Sendable {
    private let session: URLSession
    static let endpoint = URL(string: "https://openrouter.ai/api/alpha/decisions")!

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 6
            configuration.timeoutIntervalForResource = 8
            self.session = URLSession(configuration: configuration)
        }
    }

    func decide(messages: [AIRoutingDecision.Message], key: String) async throws -> Data {
        try Task.checkCancellation()
        let body = try AIRoutingDecision.request(messages: messages)
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 6)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw JevDecisionError.invalidResponse }
        guard http.statusCode == 200 else { throw JevDecisionError.http(http.statusCode) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 65_536 else { throw JevDecisionError.invalidResponse }
            data.append(byte)
        }
        return data
    }
}
