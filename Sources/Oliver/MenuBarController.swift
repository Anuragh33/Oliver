import AppKit
import SwiftUI

/// Menu bar controller — shows icon in status bar
class MenuBarController {
    private var statusItem: NSStatusItem?
    private var overlayWindow: OverlayWindow

    init(overlayWindow: OverlayWindow) {
        self.overlayWindow = overlayWindow

        // Check if menu bar icon should be shown (default: true)
        let key = "showMenuBarIcon"
        let showIcon = UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
        if showIcon {
            showStatusBarIcon()
        }

        // Listen for changes to the setting
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarPrefChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    private func showStatusBarIcon() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Oliver")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show/Hide Overlay", action: #selector(toggleOverlay), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Capture Screen", action: #selector(captureScreen), keyEquivalent: "c"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About Oliver", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func hideStatusBarIcon() {
        statusItem = nil  // Removing the reference removes it from the bar
    }

    @objc private func menuBarPrefChanged() {
        let showIcon = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        if showIcon {
            showStatusBarIcon()
        } else {
            hideStatusBarIcon()
        }
    }

    @objc private func toggleOverlay() {
        overlayWindow.toggleVisibility()
    }

    @objc private func captureScreen() {
        // Show the overlay first if hidden
        if overlayWindow.isHiddenByUser {
            overlayWindow.show()
            overlayWindow.enableInteraction()
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Oliver"
        alert.informativeText = "AI-powered overlay assistant\nInvisible to screen sharing\n\nBuilt with love by Anuragh\nv1.2.1\n\nPress Cmd+Shift+H to show/hide the overlay"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}