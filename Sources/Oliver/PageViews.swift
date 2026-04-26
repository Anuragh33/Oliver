import SwiftUI

// MARK: - Dashboard Page

struct DashboardPage: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Dashboard")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                // Status cards
                HStack(spacing: 10) {
                    StatusCard(
                        icon: "eye.slash",
                        title: "Overlay",
                        detail: "Active",
                        color: .green
                    )
                    StatusCard(
                        icon: "eye.slash.fill",
                        title: "Invisible",
                        detail: UserDefaults.standard.object(forKey: "invisibleToSharing") == nil || UserDefaults.standard.bool(forKey: "invisibleToSharing") ? "Yes" : "No",
                        color: (UserDefaults.standard.object(forKey: "invisibleToSharing") == nil || UserDefaults.standard.bool(forKey: "invisibleToSharing")) ? .green : .orange
                    )
                    StatusCard(
                        icon: "bubble.left.and.bubble.right",
                        title: "Messages",
                        detail: "\(viewModel.messages.count)",
                        color: .blue
                    )
                }

                HStack(spacing: 10) {
                    StatusCard(
                        icon: "lock.shield",
                        title: "Accessibility",
                        detail: ScreenReaderService.hasAccessibilityPermission() ? "Granted" : "Denied",
                        color: ScreenReaderService.hasAccessibilityPermission() ? .green : .yellow
                    )
                    StatusCard(
                        icon: "record.circle",
                        title: "Screen Record",
                        detail: ScreenReaderService.hasScreenRecordingPermission() ? "Granted" : "Denied",
                        color: ScreenReaderService.hasScreenRecordingPermission() ? .green : .yellow
                    )
                }

                HStack(spacing: 10) {
                    StatusCard(
                        icon: "mic",
                        title: "Speech",
                        detail: SpeechService.hasPermission() ? "Granted" : "Denied",
                        color: SpeechService.hasPermission() ? .green : .yellow
                    )
                    StatusCard(
                        icon: "brain",
                        title: "AI Model",
                        detail: UserDefaults.standard.string(forKey: "ollamaModel") ?? "deepseek-v3.2",
                        color: .purple
                    )
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Quick actions
                Text("Quick Actions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                VStack(spacing: 8) {
                    ActionButton(
                        icon: "text.viewfinder",
                        title: "Capture Screen",
                        subtitle: "Read visible content & ask AI"
                    ) {
                        viewModel.captureAndQuery()
                    }

                    ActionButton(
                        icon: "trash",
                        title: "Clear Chat",
                        subtitle: "Remove all messages"
                    ) {
                        viewModel.clearMessages()
                    }
                }

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Audio Page (with real STT)

struct AudioPage: View {
    @ObservedObject var speechService: SpeechService
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject var systemAudio: SystemAudioCapture
    @ObservedObject var aiService: OllamaService
    @AppStorage("sttProvider") private var sttProvider = "system"
    @State private var isTranscribing = false
    @State private var whisperTranscription = ""
    @State private var transcribeError = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Audio Input")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                // STT Provider picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Speech-to-Text Provider")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))

                    Picker("Provider", selection: $sttProvider) {
                        Text("System (macOS)").tag("system")
                        Text("OpenAI Whisper").tag("whisper")
                    }
                    .pickerStyle(.segmented)

                    if sttProvider == "whisper" {
                        Text("Uses OpenAI Whisper API for higher accuracy. Requires API key in Settings.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                // Microphone recording section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Microphone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    // Audio level meter
                    if speechService.isRecording {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Audio Level")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))

                            AudioLevelBar(level: speechService.audioLevel)
                        }
                    }

                    // Record button
                    HStack(spacing: 12) {
                        Button(action: {
                            if speechService.isRecording {
                                speechService.stopRecording()
                                // Auto-send transcription as chat message
                                let transcription = speechService.currentTranscription
                                if !transcription.isEmpty {
                                    Task {
                                        await viewModel.sendStreaming(message: transcription)
                                    }
                                }
                            } else {
                                speechService.startRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(speechService.isRecording ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                                    .frame(width: 56, height: 56)

                                if speechService.isRecording {
                                    // Pulsing recording indicator
                                    Circle()
                                        .stroke(Color.red, lineWidth: 2)
                                        .frame(width: 56, height: 56)
                                        .scaleEffect(speechService.isRecording ? 1.2 : 1.0)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speechService.isRecording)

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.red)
                                        .frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(speechService.isRecording ? "Recording..." : "Tap to record")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                            if speechService.isRecording {
                                Text("Speak now — auto-stops after \(Int(speechService.silenceTimeout))s of silence")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                }

                // System Audio Capture section
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Audio")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    HStack(spacing: 12) {
                        Button(action: {
                            if systemAudio.isCapturing {
                                systemAudio.stopCapture()
                            } else {
                                systemAudio.startCapture()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(systemAudio.isCapturing ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                                    .frame(width: 44, height: 44)

                                Image(systemName: systemAudio.isCapturing ? "stop.circle.fill" : "speaker.wave.2")
                                    .font(.system(size: 18))
                                    .foregroundStyle(systemAudio.isCapturing ? .orange : .blue)
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(systemAudio.isCapturing ? "Capturing system audio" : "Capture system audio")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                            Text("Records what's playing through your speakers")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                        }

                        Spacer()

                        if systemAudio.isCapturing {
                            AudioLevelBar(level: systemAudio.audioLevel)
                                .frame(width: 60)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                    // Transcribe captured audio button
                    if !systemAudio.isCapturing {
                        Button(action: transcribeSystemAudio) {
                            HStack(spacing: 6) {
                                if isTranscribing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "doc.text.viewfinder")
                                        .font(.system(size: 12))
                                }
                                Text(isTranscribing ? "Transcribing..." : "Transcribe captured audio")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.purple.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .disabled(isTranscribing)
                    }

                    // Whisper transcription result
                    if !whisperTranscription.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Transcription")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.purple.opacity(0.7))
                            }

                            Text(whisperTranscription)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                            Button(action: {
                                Task {
                                    await viewModel.sendStreaming(message: whisperTranscription)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 12))
                                    Text("Send as message")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Transcription error
                    if !transcribeError.isEmpty {
                        Text(transcribeError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }

                // Live transcription (while recording)
                if speechService.isRecording && !speechService.currentTranscription.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Live Transcription")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))

                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                        }

                        Text(speechService.currentTranscription)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                    }
                }

                // Last transcription
                if !speechService.isRecording && !speechService.currentTranscription.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last Transcription")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        Text(speechService.currentTranscription)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                        Button(action: {
                            let text = speechService.currentTranscription
                            Task {
                                await viewModel.sendStreaming(message: text)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 12))
                                Text("Send as message")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Permission warning
                if !SpeechService.hasPermission() {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text("Speech permission required")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                            Text("Grant microphone & speech recognition access in System Settings")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Button("Grant") {
                            speechService.requestPermission()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.2)))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.1)))
                }

                Spacer()
            }
            .padding(16)
        }
    }

    /// Transcribe system audio using Whisper API
    private func transcribeSystemAudio() {
        guard let wavData = systemAudio.exportWAV() else {
            transcribeError = "No audio captured yet. Start and stop capture first."
            return
        }

        isTranscribing = true
        whisperTranscription = ""
        transcribeError = ""

        Task {
            do {
                let result = try await aiService.transcribeAudio(wavData: wavData)
                await MainActor.run {
                    whisperTranscription = result
                    isTranscribing = false
                    if result.isEmpty {
                        transcribeError = "Transcription returned empty result."
                    }
                }
            } catch {
                await MainActor.run {
                    transcribeError = "Transcription failed: \(error.localizedDescription)"
                    isTranscribing = false
                }
            }
        }
    }
}

// MARK: - Audio Level Bar

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)

                Rectangle()
                    .fill(
                        level > 0.05 ? Color.green : Color.white.opacity(0.3)
                    )
                    .frame(width: CGFloat(min(CGFloat(level * 15), geo.size.width)), height: 4)
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
    }
}

// MARK: - History Page

struct HistoryPage: View {
    @ObservedObject var chatHistory: ChatHistoryManager
    @ObservedObject var viewModel: OverlayViewModel
    @State private var selectedSessionId: UUID?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("History")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    if !chatHistory.sessions.isEmpty {
                        Button(action: {
                            chatHistory.clearAll()
                        }) {
                            Text("Clear All")
                                .font(.system(size: 10))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if chatHistory.sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("No chat history yet")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("Conversations will be saved automatically")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(chatHistory.sessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: selectedSessionId == session.id,
                            onSelect: {
                                loadSession(session)
                            },
                            onDelete: {
                                chatHistory.deleteSession(session.id)
                            }
                        )
                    }
                }

                Spacer()
            }
            .padding(16)
        }
    }

    private func loadSession(_ session: ChatSession) {
        selectedSessionId = session.id

        // Restore messages
        var restoredMessages: [ChatMessageData] = []
        for msg in session.messages {
            let role: MessageRole
            switch msg.role {
            case "user": role = .user
            case "assistant": role = .assistant
            default: role = .system
            }
            restoredMessages.append(ChatMessageData(role: role, content: msg.content))
        }
        viewModel.messages = restoredMessages
    }
}

struct SessionRow: View {
    let session: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(session.messages.count) messages")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))

                    Text("·")
                        .foregroundStyle(.white.opacity(0.2))

                    Text(timeAgo)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.03))
        )
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Dev Space Page

struct DevSpacePage: View {
    @State private var codeText = ""
    @State private var outputText = ""
    @State private var selectedLanguage = "Python"
    @ObservedObject var viewModel: OverlayViewModel
    let languages = ["Python", "JavaScript", "Swift", "Rust", "Go", "SQL", "Shell"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Dev Space")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    // Language picker
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 10))
                }

                // Code editor
                VStack(alignment: .leading, spacing: 4) {
                    Text("Code")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    TextEditor(text: $codeText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.9))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120, maxHeight: 200)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: {
                        // Send code to AI for review/explanation
                        Task {
                            let prompt = "Explain or improve this \(selectedLanguage) code:\n```\n\(codeText)\n```"
                            await viewModel.sendStreaming(message: prompt)
                        }
                    }) {
                        Label("Ask AI", systemImage: "brain")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.15)))
                    .disabled(codeText.isEmpty)

                    Button(action: {
                        // Capture screen context and ask AI about it
                        viewModel.captureAndQuery()
                    }) {
                        Label("Capture + Ask", systemImage: "text.viewfinder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.purple.opacity(0.15)))

                    Spacer()

                    Button(action: {
                        codeText = ""
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.3))
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Notes / scratchpad area
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    TextEditor(text: $outputText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 60, maxHeight: 120)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Responses Page

struct ResponsesPage: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var selectedMessageIndex: Int?
    @State private var searchText = ""

    /// All assistant responses
    private var responses: [ChatMessageData] {
        viewModel.messages.filter { $0.role == .assistant }
    }

    /// Filtered responses based on search
    private var filteredResponses: [ChatMessageData] {
        if searchText.isEmpty {
            return responses
        }
        return responses.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Responses")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(responses.count) responses")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("Search responses...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                if filteredResponses.isEmpty {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.2))
                        Text(searchText.isEmpty ? "No AI responses yet" : "No matching responses")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("Chat with Oliver and responses will appear here")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.top, 30)
                    .frame(maxWidth: .infinity)
                } else {
                    // Response cards
                    ForEach(Array(filteredResponses.enumerated()), id: \.offset) { index, response in
                        ResponseCard(
                            message: response,
                            index: index,
                            isSelected: selectedMessageIndex == index,
                            onSelect: { selectedMessageIndex = index }
                        )
                    }
                }

                Spacer()
            }
            .padding(16)
        }
    }
}

struct ResponseCard: View {
    let message: ChatMessageData
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with index and time
            HStack {
                Text("#\(index + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.15)))

                Spacer()

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Content preview
            Text(message.content)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(isSelected ? nil : 3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
    }
}

// MARK: - Shortcuts Page

struct ShortcutsPage: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Keyboard Shortcuts")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                ShortcutRow(keyboard: "Cmd + Shift + H", description: "Toggle overlay visibility")
                ShortcutRow(keyboard: "Cmd + Shift + C", description: "Capture screen & ask AI")

                Divider()
                    .background(Color.white.opacity(0.1))

                Text("Global Hotkeys")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text("These shortcuts work even when Oliver is not the active app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Reusable Components

struct StatusCard: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))

            Text(detail)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.blue.opacity(0.15)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}

struct ShortcutRow: View {
    let keyboard: String
    let description: String

    var body: some View {
        HStack {
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            HStack(spacing: 4) {
                ForEach(keyboard.components(separatedBy: " + "), id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
                }
            }
        }
        .padding(.vertical, 6)
    }
}