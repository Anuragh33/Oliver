import AppKit
import SwiftUI

/// Global keyboard shortcuts for Oliver
/// Cmd+Shift+H = Toggle overlay visibility
/// Cmd+Shift+C = Capture screen & query AI
class HotkeyManager {
    private var toggleAction: (() -> Void)?
    private var captureAction: (() -> Void)?

    init() {}

    func registerActions(toggle: @escaping () -> Void, capture: @escaping () -> Void) {
        self.toggleAction = toggle
        self.captureAction = capture

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Local monitor — catches events when our app IS focused
            // Only trigger on initial key press (not repeats) and when no text field is first responder
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                if self.handleKeyEvent(event, isLocal: true) {
                    return nil // consumed
                }
                return event
            }

            // Global monitor — catches events when our app is NOT focused
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                _ = self?.handleKeyEvent(event, isLocal: false)
            }
        }
    }

    /// Returns true if the event was consumed (shortcut triggered)
    private func handleKeyEvent(_ event: NSEvent, isLocal: Bool) -> Bool {
        // Ignore key repeats (holding down the key)
        guard !event.isARepeat else { return false }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard mods.contains(.command) && mods.contains(.shift) else { return false }

        // In local monitor (overlay is focused), only trigger if first responder
        // is NOT a text input field. This prevents hotkeys from firing while typing.
        if isLocal {
            guard let window = event.window else { return false }
            // If first responder responds to text input actions, skip hotkey
            if let responder = window.firstResponder as? NSView,
               responder.responds(to: #selector(NSText.insertText(_:))) {
                return false
            }
        }

        // keyCode 4 = H, keyCode 8 = C
        switch event.keyCode {
        case 4: // Cmd+Shift+H = toggle overlay
            toggleAction?()
            return true
        case 8: // Cmd+Shift+C = capture screen
            captureAction?()
            return true
        default:
            return false
        }
    }
}