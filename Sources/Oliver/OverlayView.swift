import SwiftUI
import AppKit
import ServiceManagement

/// The main overlay view — renders in the transparent NSPanel
class OverlayView: NSView {
    private var hostingView: NSHostingView<OverlayRootView>?
    private let aiService: OllamaService
    private let screenReader: ScreenReaderService
    private let speechService: SpeechService
    private let chatHistory: ChatHistoryManager
    private let systemAudio: SystemAudioCapture

    init(aiService: OllamaService, screenReader: ScreenReaderService, speechService: SpeechService, chatHistory: ChatHistoryManager, systemAudio: SystemAudioCapture) {
        self.aiService = aiService
        self.screenReader = screenReader
        self.speechService = speechService
        self.chatHistory = chatHistory
        self.systemAudio = systemAudio
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let contentView = OverlayRootView(
            aiService: aiService,
            screenReader: screenReader,
            speechService: speechService,
            chatHistory: chatHistory,
            systemAudio: systemAudio
        )
        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        addSubview(hosting)
        self.hostingView = hosting

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}

// MARK: - Root View (Sidebar + Content)

struct OverlayRootView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject var navState: NavigationState
    @ObservedObject var speechService: SpeechService
    @ObservedObject var chatHistory: ChatHistoryManager
    @ObservedObject var systemAudio: SystemAudioCapture
    @State private var inputText = ""
    @State private var isExpanded = true  // Start expanded so users can see the UI immediately
    @State private var currentSessionId: UUID?
    @AppStorage("overlayOpacity") private var overlayOpacity = 0.85
    @AppStorage("overlayWidth") private var overlayWidth = 420.0

    init(aiService: OllamaService, screenReader: ScreenReaderService, speechService: SpeechService, chatHistory: ChatHistoryManager, systemAudio: SystemAudioCapture) {
        self.viewModel = OverlayViewModel(aiService: aiService, screenReader: screenReader)
        self.navState = NavigationState()
        self.speechService = speechService
        self.chatHistory = chatHistory
        self.systemAudio = systemAudio
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Spacer()

            // Main card
            VStack(spacing: 0) {
                // Header bar (always visible)
                headerBar

                // Expanded content: sidebar + page
                if isExpanded {
                    HStack(spacing: 0) {
                        // Sidebar (only when expanded)
                        SidebarView(navState: navState)

                        // Content area — switches based on selected page
                        contentArea
                    }
                    .frame(height: 380)

                    // Input area (always visible when expanded)
                    inputArea
                }
            }
            .frame(width: isExpanded ? CGFloat(overlayWidth) : 260)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(overlayOpacity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding([.trailing, .bottom], 20)
        .onReceive(NotificationCenter.default.publisher(for: .overlaySizeChanged)) { _ in
            // Force layout update when overlay width changes
            withAnimation(.easeInOut(duration: 0.2)) {
                // The @AppStorage overlayWidth will automatically update
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(viewModel.isStreaming ? Color.orange : Color.green)
                .frame(width: 8, height: 8)

            Text("Oliver")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            if viewModel.isStreaming {
                Text("thinking...")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // New chat button
            if isExpanded {
                Button(action: startNewChat) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("New chat")
            }

            // Expand/collapse button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)

            // Close button
            if isExpanded {
                Button(action: {
                    // Save current chat before clearing
                    if !viewModel.messages.isEmpty {
                        chatHistory.saveSession(messages: viewModel.messages)
                    }
                    viewModel.clearMessages()
                    currentSessionId = nil
                    isExpanded = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch navState.selectedPage {
        case .chat:
            ChatPage(viewModel: viewModel)
        case .dashboard:
            DashboardPage(viewModel: viewModel)
        case .audio:
            AudioPage(speechService: speechService, viewModel: viewModel, systemAudio: systemAudio, aiService: viewModel.aiService)
        case .settings:
            SettingsPage()
        case .shortcuts:
            ShortcutsPage()
        case .devSpace:
            DevSpacePage(viewModel: viewModel)
        case .responses:
            ResponsesPage(viewModel: viewModel)
        case .history:
            HistoryPage(chatHistory: chatHistory, viewModel: viewModel)
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Screen capture button
                Button(action: {
                    viewModel.captureAndQuery()
                }) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Capture screen content")

                // Microphone / voice input button
                Button(action: {
                    if speechService.isRecording {
                        speechService.stopRecording()
                        // Send the transcription as a chat message
                        let transcription = speechService.currentTranscription
                        if !transcription.isEmpty {
                            inputText = transcription
                            sendMessage()
                        }
                    } else {
                        speechService.startRecording()
                    }
                }) {
                    Image(systemName: speechService.isRecording ? "waveform.circle.fill" : "mic")
                        .font(.system(size: 14))
                        .foregroundStyle(speechService.isRecording ? .red : .white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(speechService.isRecording ? "Stop recording" : "Voice input")

                TextField("Ask anything...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await viewModel.sendStreaming(message: text)
        }
    }

    private func startNewChat() {
        // Save current session if it has messages
        if !viewModel.messages.isEmpty {
            chatHistory.saveSession(messages: viewModel.messages)
        }
        viewModel.clearMessages()
        currentSessionId = nil
    }
}

// MARK: - Chat Page

struct ChatPage: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.messages.isEmpty {
                        // Empty state
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.2))
                            Text("Start a conversation")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("Type below or use Cmd+Shift+C to capture your screen")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.top, 40)
                    }

                    ForEach(viewModel.messages) { msg in
                        MessageBubble(message: msg)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Settings Page

struct SettingsPage: View {
    @AppStorage("ollamaModel") private var ollamaModel = "deepseek-v3.2"
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "https://ollama.com/v1"
    @AppStorage("ollamaApiKey") private var ollamaApiKey = ""
    @AppStorage("overlayOpacity") private var overlayOpacity = 0.85
    @AppStorage("overlayWidth") private var overlayWidth = 420.0
    @AppStorage("autoCapture") private var autoCapture = false
    @AppStorage("captureInterval") private var captureInterval = 30.0
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("invisibleToSharing") private var invisibleToSharing = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    let models = ["deepseek-v3.2", "qwen3.5:397b", "glm-5.1", "kimi-k2.5", "gpt-oss:120b", "gemma4:31b"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                // AI Model section
                settingsSectionHeader("AI Model")

                Picker("Model", selection: $ollamaModel) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                TextField("Base URL", text: $ollamaBaseURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))

                SecureField("API Key (optional)", text: $ollamaApiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))

                Divider().background(Color.white.opacity(0.1))

                // Overlay section
                settingsSectionHeader("Overlay")

                HStack {
                    Text("Opacity")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(Int(overlayOpacity * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Slider(value: $overlayOpacity, in: 0.3...1.0, step: 0.05)

                HStack {
                    Text("Width")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(Int(overlayWidth))px")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Slider(value: $overlayWidth, in: 280...600, step: 20)

                Divider().background(Color.white.opacity(0.1))

                // Auto-capture section
                settingsSectionHeader("Auto-Capture")

                Toggle("Auto-capture screen", isOn: $autoCapture)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if autoCapture {
                    HStack {
                        Text("Interval: \(Int(captureInterval))s")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                        Slider(value: $captureInterval, in: 10...120, step: 10)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // General section
                settingsSectionHeader("General")

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!LaunchAtLoginManager.isRunningAsApp)
                    .onChange(of: launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                    }

                if !LaunchAtLoginManager.isRunningAsApp {
                    Text("Only available when running as .app bundle")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Toggle("Invisible to Screen Sharing", isOn: $invisibleToSharing)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if invisibleToSharing {
                    Text("Overlay is hidden from Zoom, Meet, Teams, etc.")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.7))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("Overlay is VISIBLE to screen sharing apps!")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                }

                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Spacer()
            }
            .padding(16)
        }
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard LaunchAtLoginManager.isRunningAsApp else { return }
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[Settings] Launch at login error: \(error)")
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessageData

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(
                        message.role == .user
                        ? Color.blue.opacity(0.3)
                        : Color.white.opacity(0.08)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Data Models

enum MessageRole: String, Codable { case user, assistant, system }

struct ChatMessageData: Identifiable {
    let id = UUID()
    let role: MessageRole
    var content: String  // var for streaming token appending
    let timestamp = Date()
}

// MARK: - View Model

class OverlayViewModel: ObservableObject {
    @Published var messages: [ChatMessageData] = []
    @Published var isStreaming = false

    let aiService: OllamaService  // public so AudioPage can access it
    private let screenReader: ScreenReaderService
    var lastScreenContext: String?

    init(aiService: OllamaService, screenReader: ScreenReaderService) {
        self.aiService = aiService
        self.screenReader = screenReader
    }

    /// Send a message and stream the response token-by-token
    @MainActor
    func sendStreaming(message: String) async {
        messages.append(ChatMessageData(role: .user, content: message))
        isStreaming = true

        // Build messages for the API
        var chatMessages: [ChatMessage] = [
            .init(role: "system", content: "You are Oliver, a helpful AI assistant that can see the user's screen. Be concise and helpful.")
        ]

        if let context = lastScreenContext, !context.isEmpty {
            chatMessages.append(.init(role: "system", content: "Current screen context: \(context)"))
        }

        chatMessages.append(.init(role: "user", content: message))

        // Add a placeholder assistant message that we'll append tokens to
        messages.append(ChatMessageData(role: .assistant, content: ""))
        let responseIndex = messages.count - 1

        let stream = aiService.streamChat(messages: chatMessages)
        do {
            for try await token in stream {
                messages[responseIndex].content += token
            }
        } catch {
            messages[responseIndex].content += "\n\n(Error: \(error.localizedDescription))"
        }

        isStreaming = false
    }

    /// Capture screen and query with streaming
    @MainActor
    func captureAndQuery() {
        isStreaming = true
        let context = screenReader.captureVisibleContent()
        lastScreenContext = context

        let systemPrompt = """
        You are Oliver, an AI assistant that helps users during meetings, calls, and interviews.
        You can see what's on the user's screen. Provide concise, helpful suggestions based on the context.
        Keep responses brief (2-3 sentences max unless asked for more detail).
        """

        let userMessage: String
        if context.isEmpty {
            userMessage = "I just activated you. What can you help with?"
        } else {
            userMessage = "Here's what I see on my screen right now:\n\n\(context)\n\nWhat suggestions do you have?"
        }

        let chatMessages: [ChatMessage] = [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: userMessage)
        ]

        // Add placeholder
        messages.append(ChatMessageData(role: .assistant, content: ""))
        let responseIndex = messages.count - 1

        Task {
            let stream = aiService.streamChat(messages: chatMessages)
            do {
                for try await token in stream {
                    messages[responseIndex].content += token
                }
            } catch {
                messages[responseIndex].content += "\n\n(Error: \(error.localizedDescription))"
            }
            isStreaming = false
        }
    }

    /// Update the stored screen context without sending an AI query
    func updateScreenContext(_ context: String) {
        lastScreenContext = context
    }

    func clearMessages() {
        messages.removeAll()
        lastScreenContext = nil
    }
}