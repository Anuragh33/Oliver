import SwiftUI
import ServiceManagement

/// Settings view for configuring Oliver (macOS Settings window)
struct SettingsView: View {
    @AppStorage("ollamaModel") private var ollamaModel = "deepseek-v3.2"
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "https://ollama.com/v1"
    @AppStorage("ollamaApiKey") private var ollamaApiKey = ""
    @AppStorage("overlayOpacity") private var overlayOpacity = 0.85
    @AppStorage("overlayWidth") private var overlayWidth = 420.0
    @AppStorage("autoCapture") private var autoCapture = false
    @AppStorage("captureInterval") private var captureInterval = 30.0
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        TabView {
            GeneralSettingsView(
                launchAtLogin: $launchAtLogin,
                showMenuBarIcon: $showMenuBarIcon
            )
            .tabItem { Label("General", systemImage: "gear") }
            AISettingsView(
                ollamaModel: $ollamaModel,
                ollamaBaseURL: $ollamaBaseURL,
                ollamaApiKey: $ollamaApiKey
            )
            .tabItem { Label("AI Model", systemImage: "brain") }
            OverlaySettingsView(
                overlayOpacity: $overlayOpacity,
                overlayWidth: $overlayWidth,
                autoCapture: $autoCapture,
                captureInterval: $captureInterval
            )
            .tabItem { Label("Overlay", systemImage: "uiwindow.split.2x1") }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Binding var launchAtLogin: Bool
    @Binding var showMenuBarIcon: Bool

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    updateLaunchAtLogin(newValue)
                }
            Toggle("Show in Menu Bar", isOn: $showMenuBarIcon)
        }
        .padding()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[Settings] Launch at login error: \(error)")
            }
        }
    }
}

struct AISettingsView: View {
    @Binding var ollamaModel: String
    @Binding var ollamaBaseURL: String
    @Binding var ollamaApiKey: String

    let models = ["deepseek-v3.2", "qwen3.5:397b", "glm-5.1", "kimi-k2.5", "gpt-oss:120b", "gemma4:31b"]

    var body: some View {
        Form {
            TextField("Base URL", text: $ollamaBaseURL)
            Picker("Model", selection: $ollamaModel) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            SecureField("API Key (optional)", text: $ollamaApiKey)
        }
        .padding()
    }
}

struct OverlaySettingsView: View {
    @Binding var overlayOpacity: Double
    @Binding var overlayWidth: Double
    @Binding var autoCapture: Bool
    @Binding var captureInterval: Double

    var body: some View {
        Form {
            Slider(value: $overlayOpacity, in: 0.3...1.0, step: 0.05) {
                Text("Opacity")
            }
            Slider(value: $overlayWidth, in: 280...600, step: 20) {
                Text("Width")
            }
            Toggle("Auto-capture screen", isOn: $autoCapture)
            if autoCapture {
                Slider(value: $captureInterval, in: 10...120, step: 10) {
                    Text("Capture interval (sec)")
                }
            }
        }
        .padding()
    }
}