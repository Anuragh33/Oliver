import AppKit
import ApplicationServices
import Vision

/// Reads visible content from the screen using Accessibility APIs and OCR
class ScreenReaderService {

    // MARK: - Permission Checks

    /// Check if the app has screen recording permission
    /// CGWindowListCreateImage returns a blank image (all zeros) if permission is not granted
    static func hasScreenRecordingPermission() -> Bool {
        guard let screen = NSScreen.main else { return false }
        let rect = screen.frame
        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return false }

        // If screen recording is denied, CGWindowListCreateImage returns an image that is
        // entirely black (all pixels zero). Check a sample of pixels.
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }

        // Sample pixels from different regions
        let dataProvider = image.dataProvider
        let data = dataProvider?.data
        let buffer = CFDataGetBytePtr(data)

        guard let ptr = buffer else { return false }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow

        // Check ~10 sample points across the image
        // If ALL are zero, it's likely a blank (denied) screenshot
        var nonzeroCount = 0
        let samplePoints: [(Int, Int)] = [
            (width / 4, height / 4),
            (width / 2, height / 4),
            (width * 3 / 4, height / 4),
            (width / 4, height / 2),
            (width / 2, height / 2),
            (width * 3 / 4, height / 2),
            (width / 4, height * 3 / 4),
            (width / 2, height * 3 / 4),
            (width * 3 / 4, height * 3 / 4),
            (width / 2, height / 3),
        ]

        for (x, y) in samplePoints {
            let offset = y * bytesPerRow + x * bytesPerPixel
            if offset + bytesPerPixel <= image.width * image.height * bytesPerPixel {
                let r = ptr[offset]
                let g = ptr[offset + 1]
                let b = ptr[offset + 2]
                if r != 0 || g != 0 || b != 0 {
                    nonzeroCount += 1
                }
            }
        }

        // If no sample pixels are non-zero, screen recording permission is likely denied
        return nonzeroCount > 0
    }

    /// Check if the app has Accessibility permission
    static func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompt the user to grant screen recording permission
    /// Opens System Settings to the Screen Recording privacy pane
    static func promptScreenRecordingPermission() {
        // On macOS 13+ use the new System Settings URL
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Prompt the user to grant Accessibility permission (with system dialog)
    static func promptAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Screen Capture

    /// Capture all visible text on screen using Accessibility API
    func captureVisibleContent() -> String {
        var allText: [String] = []

        // Get the frontmost app
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return captureViaOCR()
        }

        // Use Accessibility API to read the frontmost app's content
        let element = AXUIElementCreateApplication(frontApp.processIdentifier)
        let focusedElement = getFocusedElement(from: element)

        if let focusedText = focusedElement {
            allText.append(focusedText)
        }

        // Also read the window title and menu
        if let windowTitle = getWindowTitle(from: element) {
            allText.append("Window: \(windowTitle)")
        }

        // Read all text from the app
        let appText = extractAllText(from: element)
        if !appText.isEmpty {
            allText.append(appText)
        }

        // Fallback to OCR if we didn't get much text
        if allText.joined(separator: " ").count < 20 {
            return captureViaOCR()
        }

        return allText.joined(separator: "\n")
    }

    /// Get the currently focused UI element's text
    private func getFocusedElement(from appElement: AXUIElement) -> String? {
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success else { return nil }

        let element = focusedElement as! AXUIElement
        return extractTextFromElement(element)
    }

    /// Get the window title of the frontmost app
    private func getWindowTitle(from appElement: AXUIElement) -> String? {
        var windows: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windows
        )

        guard result == .success,
              let windowList = windows as? [AXUIElement],
              let firstWindow = windowList.first else { return nil }

        var title: AnyObject?
        AXUIElementCopyAttributeValue(
            firstWindow,
            kAXTitleAttribute as CFString,
            &title
        )

        return title as? String
    }

    /// Recursively extract all text from an accessibility element
    private func extractAllText(from element: AXUIElement, depth: Int = 0) -> String {
        // Limit recursion depth
        guard depth < 5 else { return "" }

        var texts: [String] = []

        // Get this element's text
        if let text = extractTextFromElement(element) {
            texts.append(text)
        }

        // Get children
        var children: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &children
        )

        if result == .success, let childList = children as? [AXUIElement] {
            for child in childList {
                let childText = extractAllText(from: child, depth: depth + 1)
                if !childText.isEmpty {
                    texts.append(childText)
                }
            }
        }

        return texts.joined(separator: " ")
    }

    /// Extract text value from a single AXUIElement
    private func extractTextFromElement(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        if result == .success, let text = value as? String, !text.isEmpty {
            return text
        }

        // Try title
        var title: AnyObject?
        AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &title
        )

        if let text = title as? String, !text.isEmpty {
            return text
        }

        return nil
    }

    /// Fallback: capture screen and run OCR via Vision framework
    private func captureViaOCR() -> String {
        guard let screenshot = captureScreenshot() else {
            return "Unable to capture screen"
        }

        return performOCR(on: screenshot)
    }

    /// Take a screenshot of the main display
    private func captureScreenshot() -> CGImage? {
        guard let screen = NSScreen.main else { return nil }
        let rect = screen.frame

        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return nil }

        return cgImage
    }

    /// Run Vision OCR on a CGImage
    private func performOCR(on image: CGImage) -> String {
        let request = VNRecognizeTextRequest { request, error in
            // Results handled synchronously below
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return "OCR failed: \(error.localizedDescription)"
        }

        guard let results = request.results, !results.isEmpty else {
            return ""
        }
        let observations = results.compactMap { $0 as VNRecognizedTextObservation }

        let text = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }.joined(separator: "\n")

        return text
    }

    /// Get the name of the frontmost application
    func getActiveAppName() -> String? {
        return NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// Get metadata about what's on screen
    func getScreenContext() -> ScreenContext {
        let text = captureVisibleContent()
        let context = ScreenContext(
            activeApp: getActiveAppName(),
            windowTitle: getWindowTitle(of: NSWorkspace.shared.frontmostApplication?.processIdentifier),
            visibleText: text,
            timestamp: Date()
        )
        return context
    }

    private func getWindowTitle(of pid: pid_t?) -> String? {
        guard let pid = pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        return getWindowTitle(from: app)
    }
}

struct ScreenContext {
    var activeApp: String?
    var windowTitle: String?
    var visibleText: String
    var timestamp: Date
}