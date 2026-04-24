import Foundation

/// Represents a single chat session with messages
struct ChatSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var messages: [ChatMessageData.CodableVersion]
    var createdAt: Date
    var updatedAt: Date

    init(title: String, messages: [ChatMessageData]) {
        self.id = UUID()
        self.title = title
        self.messages = messages.map { $0.toCodable() }
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Auto-generate a title from the first user message
    static func makeTitle(from firstMessage: String) -> String {
        let prefix = String(firstMessage.prefix(50))
        if firstMessage.count > 50 {
            return prefix + "..."
        }
        return prefix
    }
}

extension ChatMessageData {
    /// Codable version of ChatMessageData for persistence
    struct CodableVersion: Codable {
        let role: String
        let content: String
        let timestamp: Date

        init(role: MessageRole, content: String, timestamp: Date = Date()) {
            self.role = role.rawValue
            self.content = content
            self.timestamp = timestamp
        }
    }

    func toCodable() -> CodableVersion {
        CodableVersion(role: role, content: content, timestamp: timestamp)
    }
}

// MessageRole already conforms to Codable via its String raw value in OverlayView.swift
// No need for a separate extension

// MARK: - Chat History Manager

/// Manages persistent chat history stored as JSON in Application Support
class ChatHistoryManager: ObservableObject {
    @Published var sessions: [ChatSession] = []

    private let fileURL: URL
    private let maxSessions = 50

    init() {
        // Store in ~/Library/Application Support/Oliver/chat_history.json
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Oliver", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.fileURL = dir.appendingPathComponent("chat_history.json")
        loadSessions()
    }

    // MARK: - Persistence

    func loadSessions() {
        guard let data = try? Data(contentsOf: fileURL) else {
            sessions = []
            return
        }
        sessions = (try? JSONDecoder().decode([ChatSession].self, from: data)) ?? []
    }

    func saveSessions() {
        let data = try? JSONEncoder().encode(sessions)
        try? data?.write(to: fileURL, options: .atomic)
    }

    // MARK: - Operations

    /// Save current messages as a new session
    func saveSession(messages: [ChatMessageData]) {
        guard !messages.isEmpty else { return }

        // Find first user message for title
        let firstUserMsg = messages.first(where: { $0.role == .user })
        let title = firstUserMsg.map { ChatSession.makeTitle(from: $0.content) } ?? "New Chat"

        var session = ChatSession(title: title, messages: messages)

        // If first session has the same title, update it instead
        if let existingIndex = sessions.firstIndex(where: { $0.title == title }) {
            sessions[existingIndex].messages = session.messages
            sessions[existingIndex].updatedAt = Date()
        } else {
            sessions.insert(session, at: 0)
        }

        // Trim to max
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }

        saveSessions()
    }

    /// Delete a session by ID
    func deleteSession(_ id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        saveSessions()
    }

    /// Clear all sessions
    func clearAll() {
        sessions.removeAll()
        saveSessions()
    }
}