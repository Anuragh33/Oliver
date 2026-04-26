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

    // Dynamic sizing from UserDefaults
    var overlayWidth: CGFloat {
        let width = UserDefaults.standard.double(forKey: "overlayWidth")
        return width > 0 ? CGFloat(width) : 580
    }

    var overlayOpacity: Double {
        let opacity = UserDefaults.standard.double(forKey: "overlayOpacity")
        return opacity > 0 ? opacity : 0.85
    }

    init(contentView: NSView) {
        // Read settings for initial size
        let width = UserDefaults.standard.double(forKey: "overlayWidth")
        let effectiveWidth: CGFloat = width > 0 ? CGFloat(width) : 580
        let overlayHeight: CGFloat = 470

        // Position in bottom-right corner
        let screen = NSScreen.main!
        let screenRect = screen.visibleFrame
        let x = screenRect.maxX - effectiveWidth - 20
        let y = screenRect.minY + 20
        let rect = NSRect(x: x, y: y, width: effectiveWidth, height: overlayHeight)

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

        // Listen for changes to UserDefaults (width, opacity, invisibility)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func userDefaultsChanged() {
        // Update invisibility
        let newInvisible = UserDefaults.standard.object(forKey: "invisibleToSharing") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "invisibleToSharing")
        if newInvisible != isInvisibleToSharing {
            isInvisibleToSharing = newInvisible
        }

        // Update window width
        resizeToSettings()
    }

    /// Resize the window to match the current UserDefaults width setting
    func resizeToSettings() {
        let newWidth = overlayWidth
        let screen = NSScreen.main!
        let screenRect = screen.visibleFrame
        let x = screenRect.maxX - newWidth - 20
        let currentFrame = self.frame
        let newFrame = NSRect(x: x, y: currentFrame.origin.y, width: newWidth, height: currentFrame.height)

        self.setFrame(newFrame, display: true, animate: !isHiddenByUser)

        // Post notification so SwiftUI views can update
        NotificationCenter.default.post(name: .overlaySizeChanged, object: nil)
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

// MARK: - Notification for overlay size changes

extension Notification.Name {
    static let overlaySizeChanged = Notification.Name("overlaySizeChanged")
}