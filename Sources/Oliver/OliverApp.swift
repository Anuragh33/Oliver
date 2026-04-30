import SwiftUI
import AppKit
import UserNotifications

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

        // Initialize services safely
        let ai = OllamaService()
        let reader = ScreenReaderService()
        let speech = SpeechService()
        let history = ChatHistoryManager()
        let audio = SystemAudioCapture()

        self.aiService = ai
        self.screenReader = reader
        self.speechService = speech
        self.chatHistory = history
        self.systemAudioCapture = audio

        // Create overlay view and window
        let view = OverlayView(
            aiService: ai,
            screenReader: reader,
            speechService: speech,
            chatHistory: history,
            systemAudio: audio
        )
        self.overlayView = view
        overlayWindow = OverlayWindow(contentView: view)

        // Menu bar controller
        guard let window = overlayWindow else { return }
        menuBarController = MenuBarController(
            overlayWindow: window,
            captureAction: { [weak self] in self?.captureAndQuery() }
        )

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

        // Request notification permission for launch alerts
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted {
                print("[Oliver] Notification permission denied")
            }
        }

        // Show a welcome notification so users know the app is running
        showLaunchNotification()
    }

    // MARK: - Launch Notification

    private func showLaunchNotification() {
        // Always show a visible alert so users know the app started
        showWelcomeAlert()

        // Also schedule a notification for subsequent launches
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "oliver.hasLaunchedBefore")
        if !isFirstLaunch {
            let content = UNMutableNotificationContent()
            content.title = "Oliver is Running"
            content.body = "Press Cmd+Shift+H to open the overlay."
            content.sound = nil

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
            let request = UNNotificationRequest(identifier: "oliver.ready", content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[Oliver] Failed to show notification: \(error)")
                }
            }
        }

        UserDefaults.standard.set(true, forKey: "oliver.hasLaunchedBefore")
    }

    private func showWelcomeAlert() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Oliver is Running"
            alert.informativeText = "Oliver lives in your menu bar (eye icon).\n\n• Cmd+Shift+H — Open overlay\n• Cmd+Shift+C — Capture screen\n\nYou can close this alert. Oliver keeps running."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Got it")
            alert.runModal()
        }
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