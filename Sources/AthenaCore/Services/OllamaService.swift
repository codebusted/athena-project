import Foundation

public enum OllamaStatus: Equatable, Sendable {
    case checking
    case ready(model: String)
    case notRunning
    case modelMissing(model: String)
    case error(String)

    public var isReady: Bool { if case .ready = self { true } else { false } }
}

public enum OllamaError: Error, LocalizedError, Equatable {
    case notRunning
    case modelMissing(String)
    case timedOut
    case http(Int, String)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning: "Ollama is not running. Start it with `ollama serve` (or open the Ollama app)."
        case .modelMissing(let m): "Model \(m) is not downloaded. Run `ollama pull \(m)`."
        case .timedOut: "The local model took too long to respond."
        case .http(let code, let body): "Ollama returned HTTP \(code): \(body.prefix(200))"
        case .malformed(let why): "The model returned an invalid response (\(why))."
        }
    }
}

/// Talks to the local Ollama HTTP API (localhost only). Knows nothing about learning logic:
/// callers pass prompts plus a JSON schema and get back decoded values.
public struct OllamaService: Sendable {
    public var baseURL: URL
    public var model: String
    public var think: Bool
    public var timeout: TimeInterval

    public init(baseURL: URL = URL(string: "http://localhost:11434")!, model: String = "qwen3:4b",
                think: Bool = false, timeout: TimeInterval = 90) {
        self.baseURL = baseURL
        self.model = model
        self.think = think
        self.timeout = timeout
    }

    public func status() async -> OllamaStatus {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .error("Unexpected response") }
            struct Tags: Decodable { struct M: Decodable { let name: String }; let models: [M] }
            let names = try JSONDecoder().decode(Tags.self, from: data).models.map(\.name)
            return Self.modelIsAvailable(model, in: names) ? .ready(model: model) : .modelMissing(model: model)
        } catch {
            return .notRunning
        }
    }

    static func modelIsAvailable(_ model: String, in names: [String]) -> Bool {
        let wanted = model.contains(":") ? model : model + ":latest"
        return names.contains(wanted) || names.contains(model)
    }

    /// One non-streaming /api/chat call constrained to `schema`, decoded as `T`.
    /// `think` overrides the service default for this call (e.g. enable reasoning for answer verification).
    public func chatJSON<T: Decodable>(
        system: String, user: String, schema: String, think: Bool? = nil, temperature: Double = 0.4,
        as type: T.Type
    ) async throws -> T {
        let content = try await chat(system: system, user: user, schema: schema, think: think ?? self.think,
                                     temperature: temperature)
        if ProcessInfo.processInfo.environment["ATHENA_DEBUG"] != nil {
            FileHandle.standardError.write(Data("── \(model) raw response ──\n\(content)\n".utf8))
        }
        guard let json = Self.extractJSONObject(from: content) else { throw OllamaError.malformed("no JSON object") }
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw OllamaError.malformed("JSON did not match schema")
        }
    }

    private func chat(system: String, user: String, schema: String, think: Bool, temperature: Double,
                      allowThinkField: Bool = true) async throws -> String {
        // `format` constrains decoding on models that support it; repeating the schema in the prompt keeps
        // key names right on models that only loosely follow it.
        let compactSchema = schema.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined()
        let userContent = user + "\n\nReturn only a JSON object matching this JSON Schema, using exactly these key names:\n" + compactSchema
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [["role": "system", "content": system], ["role": "user", "content": userContent]],
            "options": ["temperature": temperature],
            "keep_alive": "10m",
        ]
        if let schemaObject = try? JSONSerialization.jsonObject(with: Data(schema.utf8)) { body["format"] = schemaObject }
        if allowThinkField { body["think"] = think }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OllamaError.timedOut
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
            throw OllamaError.notRunning
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        guard code == 200 else {
            // Models without reasoning support reject the `think` field; retry once without it.
            if allowThinkField, text.contains("does not support thinking") {
                return try await chat(system: system, user: user, schema: schema, think: false,
                                      temperature: temperature, allowThinkField: false)
            }
            if code == 404, text.contains("not found") { throw OllamaError.modelMissing(model) }
            throw OllamaError.http(code, text)
        }
        struct ChatResponse: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        guard let reply = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw OllamaError.malformed("unexpected envelope")
        }
        return reply.message.content
    }

    /// Small models sometimes wrap JSON in ``` fences or emit <think> blocks even when asked not to.
    static func extractJSONObject(from text: String) -> String? {
        var s = text
        while let start = s.range(of: "<think>"), let end = s.range(of: "</think>", range: start.upperBound..<s.endIndex) {
            s.removeSubrange(start.lowerBound..<end.upperBound)
        }
        guard let first = s.firstIndex(of: "{"), let last = s.lastIndex(of: "}"), first < last else { return nil }
        return String(s[first...last])
    }
}
