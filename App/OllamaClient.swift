import Foundation

struct OllamaClient: Sendable {
    var baseURL: URL
    var session: URLSession

    init(baseURLString: String, session: URLSession = .shared) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        self.baseURL = URL(string: normalized) ?? URL(string: "http://127.0.0.1:11434")!
        self.session = session
    }

    struct ModelInfo: Sendable, Equatable, Identifiable {
        var id: String { name }
        var name: String
    }

    struct ChatTurn: Sendable, Equatable {
        var role: String
        var content: String
    }

    enum ClientError: Error, LocalizedError, Sendable, Equatable {
        case invalidURL
        case httpStatus(Int, String)
        case unreachable(String)
        case emptyResponse
        case cancelled
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Ollama URL."
            case .httpStatus(let code, let body):
                let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if snippet.isEmpty { return "Ollama returned HTTP \(code)." }
                return "Ollama HTTP \(code): \(snippet.prefix(200))"
            case .unreachable(let message):
                return "Cannot reach Ollama. \(message) Start Ollama and check Settings → AI."
            case .emptyResponse:
                return "Ollama returned an empty response."
            case .cancelled:
                return "Cancelled."
            case .decoding(let message):
                return "Could not read Ollama response: \(message)"
            }
        }
    }

    func listModels() async throws -> [ModelInfo] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await session.data(for: request)
            try throwIfNeeded(response, data: data)
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            return (decoded.models ?? []).map { ModelInfo(name: $0.name) }
        } catch let error as ClientError {
            throw error
        } catch is CancellationError {
            throw ClientError.cancelled
        } catch {
            throw ClientError.unreachable(error.localizedDescription)
        }
    }

    func chatStream(
        model: String,
        system: String,
        user: String,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        try await chatStream(
            model: model,
            system: system,
            messages: [ChatTurn(role: "user", content: user)],
            onDelta: onDelta
        )
    }

    func chatStream(
        model: String,
        system: String,
        messages: [ChatTurn],
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        var payload: [ChatMessage] = [ChatMessage(role: "system", content: system)]
        payload.append(contentsOf: messages.map { ChatMessage(role: $0.role, content: $0.content) })

        let body = ChatRequest(model: model, stream: true, messages: payload)
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ClientError.httpStatus(http.statusCode, "")
            }

            var sawContent = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard let data = trimmed.data(using: .utf8) else { continue }
                let chunk = try JSONDecoder().decode(ChatStreamChunk.self, from: data)
                if let content = chunk.message?.content, !content.isEmpty {
                    sawContent = true
                    onDelta(content)
                }
                if chunk.done == true { break }
            }
            if !sawContent {
                throw ClientError.emptyResponse
            }
        } catch is CancellationError {
            throw ClientError.cancelled
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.unreachable(error.localizedDescription)
        }
    }

    private func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpStatus(http.statusCode, body)
        }
    }
}

// MARK: - Codable payloads

private struct TagsResponse: Decodable {
    var models: [TagModel]?
}

private struct TagModel: Decodable {
    var name: String
}

private struct ChatRequest: Encodable {
    var model: String
    var stream: Bool
    var messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatStreamChunk: Decodable {
    var message: ChatMessage?
    var done: Bool?
}
