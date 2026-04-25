import AppKit
import SwiftUI

/// The core overlay window — transparent, always on top, invisible to screen sharing
/// Users can see and interact with it, but screen sharing apps (Zoom, Teams, etc.) cannot capture it
class OverlayWindow: NSPanel {
    var isHiddenByUser = true  // START HIDDEN — user activates via hotkey
    var isInteractive: Bool = false  // Start non-interactive so we don't block the screen

    /// Whether the overlay is invisible to screen sharing (sharingType = .none)
    /// When false, the overlay is VISIBLE to screen sharing apps (normal window)
    var isInvisibleToSharing: Bool = true {
        didSet {
            updateSharingType()
        }
    }

    init(contentView: NSView) {
        // Use a reasonable overlay size, NOT the full screen.
        // Full-screen transparent window blocks ALL mouse events to other apps.
        let screen = NSScreen.main!
        let screenRect = screen.visibleFrame
        // Position in bottom-right corner, 580x420 (matches expanded UI)
        let overlayWidth: CGFloat = 580
        let overlayHeight: CGFloat = 470
        let x = screenRect.maxX - overlayWidth - 20
        let y = screenRect.minY + 20
        let rect = NSRect(x: x, y: y, width: overlayWidth, height: overlayHeight)

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Read invisibility preference (default: true)
        isInvisibleToSharing = UserDefaults.standard.object(forKey: "invisibleToSharing") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "invisibleToSharing")

        // KILLER FEATURE: Invisible to screen sharing
        updateSharingType()

        // Window properties
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating + 1
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false

        // CRITICAL: Start as click-through so we don't block the entire screen
        // User activates overlay via Cmd+Shift+H hotkey
        self.ignoresMouseEvents = true
        isInteractive = false

        self.contentView = contentView

        // Listen for changes to invisibility preference
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invisibilityPrefChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func invisibilityPrefChanged() {
        let newValue = UserDefaults.standard.object(forKey: "invisibleToSharing") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "invisibleToSharing")
        if newValue != isInvisibleToSharing {
            isInvisibleToSharing = newValue
        }
    }

    // Allow this panel to become key so text fields work
    override var canBecomeKey: Bool {
        return true
    }

    func show() {
        isHiddenByUser = false
        ignoresMouseEvents = false
        isInteractive = true
        // Use orderFront instead of makeKeyAndOrderFront to avoid stealing
        // keyboard focus from the user's active application
        orderFront(nil)
    }

    func hide() {
        isHiddenByUser = true
        orderOut(nil)
    }

    func toggleVisibility() {
        if isHiddenByUser {
            show()
        } else {
            hide()
        }
    }

    /// Enable mouse interaction on the overlay
    /// Also make key so text input works (needed for chat input)
    func enableInteraction() {
        isInteractive = true
        ignoresMouseEvents = false
        makeKey()  // Need key status for text fields to work
    }

    /// Disable mouse interaction (let clicks pass through)
    /// The overlay is still VISIBLE but clicks go through to apps behind it
    func disableInteraction() {
        isInteractive = false
        ignoresMouseEvents = true
    }

    /// Update sharingType based on isInvisibleToSharing preference
    private func updateSharingType() {
        if isInvisibleToSharing {
            // Invisible to screen sharing — Zoom/Meet/Teams can't see this window
            self.sharingType = .none
            print("[Oliver] Invisibility ON — overlay hidden from screen sharing")
        } else {
            // Visible to screen sharing — behaves as a normal window
            // .readWrite makes the window fully visible to screen capture
            self.sharingType = .readWrite
            print("[Oliver] Invisibility OFF — overlay visible to screen sharing")
        }
    }

    /// Toggle invisibility to screen sharing
    func toggleInvisibility() {
        isInvisibleToSharing.toggle()
    }
}