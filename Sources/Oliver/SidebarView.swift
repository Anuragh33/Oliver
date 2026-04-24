import SwiftUI

// MARK: - Navigation State

/// Manages which page is currently active in the sidebar
class NavigationState: ObservableObject {
    @Published var selectedPage: Page = .chat
}

enum Page: String, CaseIterable {
    case chat = "Chat"
    case dashboard = "Dashboard"
    case audio = "Audio"
    case history = "History"
    case settings = "Settings"
    case shortcuts = "Shortcuts"

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .dashboard: return "square.grid.2x2"
        case .audio: return "mic"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .shortcuts: return "keyboard"
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var navState: NavigationState

    var body: some View {
        VStack(spacing: 0) {
            // Logo area
            logoArea

            // Navigation items
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Page.allCases, id: \.self) { page in
                        SidebarButton(
                            page: page,
                            isSelected: navState.selectedPage == page,
                            action: { navState.selectedPage = page }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            Spacer()

            // Footer
            footerArea
        }
        .frame(width: 160)
        .background(Color.black.opacity(0.4))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: - Logo

    private var logoArea: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue.opacity(0.3)))

            Text("Oliver")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Footer

    private var footerArea: some View {
        VStack(spacing: 4) {
            // Permission status indicators
            if !ScreenReaderService.hasAccessibilityPermission() {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("Accessibility")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !ScreenReaderService.hasScreenRecordingPermission() {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("Screen Record")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !SpeechService.hasPermission() {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("Speech")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 10)

            // Version
            Text("v1.1")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 10)
        }
    }
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let page: Page
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: page.icon)
                    .font(.system(size: 12))
                    .frame(width: 18)

                Text(page.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                Spacer()
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}