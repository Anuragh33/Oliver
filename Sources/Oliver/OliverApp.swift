import SwiftUI
import AppKit

@main
struct OliverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: OverlayWindow?
    var menuBarController: MenuBarController?
    var screenReader: ScreenReaderService?
    var aiService: OllamaService?
    var overlayView: OverlayView?
    var hotkeyManager: HotkeyManager?
    var speechService: SpeechService?
    var chatHistory: ChatHistoryManager?
    var launchAtLoginManager: LaunchAtLoginManager?
    var systemAudioCapture: SystemAudioCapture?

    // Permission retry timers
    private var accessibilityRetryTimer: Timer?
    private var screenRecordingRetryTimer: Timer?
    private var permissionAlertShown = false

    // Auto-capture timer
    private var autoCaptureTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make the app a background/accessory app (no dock icon, no main menu)
        NSApp.setActivationPolicy(.accessory)

        // Initialize services
        aiService = OllamaService()
        screenReader = ScreenReaderService()
        speechService = SpeechService()
        chatHistory = ChatHistoryManager()
        launchAtLoginManager = LaunchAtLoginManager()
        systemAudioCapture = SystemAudioCapture()

        // Create overlay view and window
        overlayView = OverlayView(
            aiService: aiService!,
            screenReader: screenReader!,
            speechService: speechService!,
            chatHistory: chatHistory!,
            systemAudio: systemAudioCapture!
        )
        overlayWindow = OverlayWindow(contentView: overlayView!)

        // Menu bar controller
        menuBarController = MenuBarController(overlayWindow: overlayWindow!)

        // Register global hotkeys
        hotkeyManager = HotkeyManager()
        hotkeyManager?.registerActions(
            toggle: { [weak self] in self?.overlayWindow?.toggleVisibility() },
            capture: { [weak self] in self?.captureAndQuery() }
        )

        // Defer permission checks to avoid freezing macOS with system dialogs on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPermissionsOnLaunch()
        }

        // Setup auto-capture timer (watches UserDefaults for changes)
        setupAutoCaptureTimer()

        // DON'T auto-show the overlay — start hidden!
        // User presses Cmd+Shift+H to show it. This prevents the full-screen
        // transparent window from blocking all interaction on launch.

        print("[Oliver] App launched successfully!")
        print("[Oliver] Hotkeys: Cmd+Shift+H = toggle, Cmd+Shift+C = capture")
        print("[Oliver] Overlay is invisible to screen sharing (sharingType = .none)")
        print("[Oliver] Press Cmd+Shift+H to show the overlay")
    }

    // MARK: - Permission Checks with Retry

    private func checkPermissionsOnLaunch() {
        let hasAccessibility = ScreenReaderService.hasAccessibilityPermission()
        let hasScreenRecording = ScreenReaderService.hasScreenRecordingPermission()

        if hasAccessibility && hasScreenRecording {
            print("[Oliver] All permissions granted!")
        }

        if !hasAccessibility {
            print("[Oliver] Accessibility permission missing — prompting user")
            _ = ScreenReaderService.promptAccessibilityPermission()
            startAccessibilityRetryLoop()
        }

        if !hasScreenRecording {
            print("[Oliver] Screen recording permission missing — prompting user")
            ScreenReaderService.promptScreenRecordingPermission()
            startScreenRecordingRetryLoop()
        }
    }

    private func startAccessibilityRetryLoop() {
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if ScreenReaderService.hasAccessibilityPermission() {
                print("[Oliver] Accessibility permission granted!")
                self.accessibilityRetryTimer?.invalidate()
                self.accessibilityRetryTimer = nil

                if self.screenRecordingRetryTimer == nil {
                    self.onAllPermissionsGranted()
                }
            }
        }
    }

    private func startScreenRecordingRetryLoop() {
        screenRecordingRetryTimer?.invalidate()
        screenRecordingRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if ScreenReaderService.hasScreenRecordingPermission() {
                print("[Oliver] Screen recording permission granted!")
                self.screenRecordingRetryTimer?.invalidate()
                self.screenRecordingRetryTimer = nil

                if self.accessibilityRetryTimer == nil {
                    self.onAllPermissionsGranted()
                }
            }
        }
    }

    private func onAllPermissionsGranted() {
        if !permissionAlertShown {
            permissionAlertShown = true
            print("[Oliver] All permissions now granted — full functionality available!")
        }
    }

    // MARK: - Auto-Capture Timer

    private func setupAutoCaptureTimer() {
        updateAutoCaptureTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func userDefaultsChanged() {
        updateAutoCaptureTimer()
    }

    private func updateAutoCaptureTimer() {
        autoCaptureTimer?.invalidate()
        autoCaptureTimer = nil

        let autoCaptureOn = UserDefaults.standard.bool(forKey: "autoCapture")
        guard autoCaptureOn else { return }

        let interval = UserDefaults.standard.double(forKey: "captureInterval")
        let effectiveInterval = interval > 0 ? interval : 30.0

        print("[Oliver] Auto-capture enabled, interval: \(effectiveInterval)s")

        autoCaptureTimer = Timer.scheduledTimer(
            withTimeInterval: effectiveInterval,
            repeats: true
        ) { [weak self] _ in
            self?.autoCaptureAndQuery()
        }
    }

    private func autoCaptureAndQuery() {
        guard let screenReader = screenReader,
              let overlayView = overlayView else { return }

        guard let window = overlayWindow, !window.isHiddenByUser else { return }

        let content = screenReader.captureVisibleContent()

        if let hostingView = overlayView.subviews.first as? NSHostingView<OverlayRootView> {
            hostingView.rootView.viewModel.updateScreenContext(content)
        }
    }

    // MARK: - Manual Capture

    private func captureAndQuery() {
        guard let screenReader = screenReader,
              let aiService = aiService else { return }

        let content = screenReader.captureVisibleContent()
        Task {
            _ = await aiService.queryWithContext(content)
        }
    }
}