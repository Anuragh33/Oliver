import Foundation

/// Ollama Cloud service — sends screen context and gets AI responses
/// Reads model/URL/API key from UserDefaults so Settings changes take effect immediately
class OllamaService: ObservableObject {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    /// Dynamic properties reading from UserDefaults (set by SettingsView @AppStorage)
    private var baseURL: String {
        UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "https://ollama.com/v1"
    }

    private var model: String {
        UserDefaults.standard.string(forKey: "ollamaModel") ?? "deepseek-v3.2"
    }

    private var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: "ollamaApiKey")
        return (key?.isEmpty ?? true) ? nil : key
    }

    /// Query the LLM with screen context
    @MainActor
    func queryWithContext(_ screenContent: String) async -> String {
        let systemPrompt = """
        You are Oliver, an AI assistant that helps users during meetings, calls, and interviews.
        You can see what's on the user's screen. Provide concise, helpful suggestions based on the context.
        Keep responses brief (2-3 sentences max unless asked for more detail).
        If the user seems to be in a meeting, offer relevant talking points or answers.
        If they're coding, offer debugging help or suggestions.
        """

        let userMessage: String
        if screenContent.isEmpty {
            userMessage = "I just activated you. What can you help with?"
        } else {
            userMessage = "Here's what I see on my screen right now:\n\n\(screenContent)\n\nWhat suggestions do you have?"
        }

        return await sendChat(messages: [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: userMessage)
        ])
    }

    /// Send a direct chat message
    @MainActor
    func sendChatMessage(_ message: String, context: String? = nil) async -> String {
        var messages: [ChatMessage] = [
            .init(role: "system", content: "You are Oliver, a helpful AI assistant that can see the user's screen. Be concise and helpful.")
        ]

        if let context = context, !context.isEmpty {
            messages.append(.init(role: "system", content: "Current screen context: \(context)"))
        }

        messages.append(.init(role: "user", content: message))
        return await sendChat(messages: messages)
    }

    /// Stream a chat response — yields tokens as they arrive
    func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let url = URL(string: "\(baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
            "max_tokens": 1024,
            "temperature": 0.7
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            let task = self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let data = data,
                      let responseString = String(data: data, encoding: .utf8) else {
                    continuation.finish()
                    return
                }

                // Parse SSE stream
                for line in responseString.components(separatedBy: "\n") {
                    if line.hasPrefix("data: ") {
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" { continue }
                        if let jsonData = jsonStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            continuation.yield(content)
                        }
                    }
                }
                continuation.finish()
            }
            task.resume()
        }
    }

    /// Send a non-streaming chat request
    @MainActor
    private func sendChat(messages: [ChatMessage]) async -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
            "max_tokens": 1024,
            "temperature": 0.7
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await session.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let content = message?["content"] as? String
            return content ?? "No response from AI."
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

struct ChatMessage {
    let role: String
    let content: String
}