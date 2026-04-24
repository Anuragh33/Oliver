import Foundation
import ServiceManagement

/// Manages launch-at-login using SMAppService (macOS 13+)
class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            updateLoginItem()
        }
    }

    init() {
        // Check current status
        if #available(macOS 13.0, *) {
            isEnabled = (SMAppService.mainApp.status == .enabled)
        } else {
            // Fallback: check via shared file list (older macOS)
            isEnabled = Self.isInLoginItemsLegacy()
        }
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                    print("[LaunchAtLogin] Registered as login item")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("[LaunchAtLogin] Unregistered from login items")
                }
            } catch {
                print("[LaunchAtLogin] Error: \(error.localizedDescription)")
                isEnabled = !isEnabled // revert
            }
        } else {
            // Fallback for older macOS
            Self.setLoginItemLegacy(enabled: isEnabled)
        }
    }

    // MARK: - Legacy Fallback (macOS 12 and earlier)

    private static func isInLoginItemsLegacy() -> Bool {
        guard let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?.takeRetainedValue() else {
            return false
        }
        let url = Bundle.main.bundleURL as CFURL
        let items = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] ?? []
        return items.contains(where: { item in
            guard let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() else { return false }
            return itemURL == url
        })
    }

    private static func setLoginItemLegacy(enabled: Bool) {
        guard let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?.takeRetainedValue() else {
            return
        }
        let url = Bundle.main.bundleURL as CFURL

        if enabled {
            LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst.takeUnretainedValue(), nil, nil, url, nil, nil)
            print("[LaunchAtLogin] Added to login items (legacy)")
        } else {
            let items = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] ?? []
            for item in items {
                if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue(), itemURL == url {
                    LSSharedFileListItemRemove(loginItems, item)
                    print("[LaunchAtLogin] Removed from login items (legacy)")
                    break
                }
            }
        }
    }
}