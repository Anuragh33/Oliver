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
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.handleKeyEvent(event) == true {
                    return nil // consumed
                }
                return event
            }

            // Global monitor — catches events when our app is NOT focused
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
            }
        }
    }

    /// Returns true if the event was consumed (shortcut triggered)
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard mods.contains(.command) && mods.contains(.shift) else { return false }

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