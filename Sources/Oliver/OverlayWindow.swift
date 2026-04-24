import AppKit
import SwiftUI

/// the core overlay window - transparent, always on top, and INVISIBLE to screen sharing (Oliver)
class OverlayWindow: NSPanel {
    var isHiddenByUser = false  // public so AppDelegate can check visibility
    var isInteractive: Bool = false

    init(contentView: NSView) {
        let screen = NSScreen.main!
        let rect = screen.visibleFrame

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // KILLER FEATURE: Invisible to screen sharing
        self.sharingType = .none

        // Window properties
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating + 1
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false

        // Start as click-through (non-interactive)
        self.ignoresMouseEvents = true
        isInteractive = false

        self.contentView = contentView
    }

    func show() {
        isHiddenByUser = false
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    func hide() {
        isHiddenByUser = true
        orderOut(nil)
    }

    func toggleVisibility() {
        if isHiddenByUser {
            show()
            enableInteraction()
        } else {
            // If visible and interactive, first disable interaction
            // If visible and click-through, hide the overlay
            if isInteractive {
                disableInteraction()
            } else {
                hide()
            }
        }
    }

    /// Enable mouse interaction on the overlay
    func enableInteraction() {
        isInteractive = true
        ignoresMouseEvents = false
    }

    /// Disable mouse interaction (let clicks pass through)
    func disableInteraction() {
        isInteractive = false
        ignoresMouseEvents = true
    }
}