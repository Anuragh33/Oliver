import AppKit
import SwiftUI

/// Menu bar controller — shows icon in status bar
class MenuBarController {
    private var statusItem: NSStatusItem?
    private var overlayWindow: OverlayWindow
    private var showMenuBarIcon: Bool
    private var captureAction: (() -> Void)?

    init(overlayWindow: OverlayWindow, captureAction: (() -> Void)? = nil) {
        self.overlayWindow = overlayWindow
        self.captureAction = captureAction
        self.showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "showMenuBarIcon")

        if showMenuBarIcon {
            showStatusBarIcon()
        }

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
        menu.addItem(withTitle: "Show/Hide Overlay", action: #selector(toggleOverlay), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Capture Screen", action: #selector(captureScreen), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "About Oliver", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Oliver", action: #selector(quitApp), keyEquivalent: "q").target = self

        statusItem?.menu = menu
    }

    private func hideStatusBarIcon() {
        statusItem = nil
    }

    @objc private func menuBarPrefChanged() {
        let showIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        if showIcon {
            showStatusBarIcon()
        } else {
            hideStatusBarIcon()
        }
    }

    @objc private func toggleOverlay() {
        overlayWindow.toggleVisibility()
    }

    @objc private func openSettings() {
        // Open the app's Settings window directly
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        // Fallback: activate the app to ensure the settings window appears
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func captureScreen() {
        // Show the overlay first if hidden
        if overlayWindow.isHiddenByUser {
            overlayWindow.show()
            overlayWindow.enableInteraction()
        }
        captureAction?()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Oliver v1.3.0"
        alert.informativeText = "AI-powered overlay assistant\nInvisible to screen sharing\n\nBuilt with love by Anuragh"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
