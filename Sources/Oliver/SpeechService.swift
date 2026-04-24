import Foundation
import Speech
import AVFoundation

/// Speech-to-text service using Apple's SFSpeechRecognizer
/// Supports real-time transcription with voice activity detection
class SpeechService: ObservableObject {
    @Published var isRecording = false
    @Published var currentTranscription = ""
    @Published var audioLevel: Float = 0.0
    @Published var permissionGranted = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var silenceTimer: Timer?
    private var lastSpeechTime: Date?

    // VAD config
    let silenceThreshold: Float = 0.015       // below this = silence
    let silenceTimeout: TimeInterval = 2.5     // stop after this much silence

    // On-device recognition (works offline, faster)
    private let prefersOnDevice = true

    init() {
        // Use the locale for the preferred language, falling back to en-US
        let locale = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0) } ?? Locale(identifier: "en-US")
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        // Prefer on-device if available (macOS 13+)
        if #available(macOS 13.0, *) {
            speechRecognizer?.supportsOnDeviceRecognition = true
        }
    }

    // MARK: - Permission

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.permissionGranted = (status == .authorized)
                if status != .authorized {
                    print("[SpeechService] Speech recognition permission denied: \(status.rawValue)")
                }
            }
        }

        // Also need microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                print("[SpeechService] Microphone permission denied")
            }
        }
    }

    static func hasPermission() -> Bool {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        return speechStatus == .authorized && micStatus == .authorized
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }

        // Check permissions first
        if !SpeechService.hasPermission() {
            requestPermission()
            return
        }

        // Cancel any existing task
        stopRecording()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let bus = 0

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device for lower latency
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = prefersOnDevice
        }

        recognitionRequest = request

        // Configure audio format
        let format = inputNode.outputFormat(forBus: bus)

        // Install tap to capture audio + measure level for VAD
        inputNode.installTap(onBus: bus, bufferSize: 1024, format: format) { [weak self] buffer, time in
            request.append(buffer)

            // Calculate RMS audio level for VAD
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if frameLength > 0, let data = channelData {
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += data[i] * data[i]
                }
                let rms = sqrtf(sum / Float(frameLength))
                DispatchQueue.main.async {
                    self?.audioLevel = rms
                    self?.processAudioLevel(rms)
                }
            }
        }

        // Prepare and start the engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[SpeechService] Failed to start audio engine: \(error)")
            return
        }

        audioEngine = engine

        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result = result {
                    self?.currentTranscription = result.bestTranscription.formattedString

                    // Mark that we just got speech
                    self?.lastSpeechTime = Date()
                    self?.resetSilenceTimer()
                }

                if let error = error {
                    // "cancelled" error is expected when we stop
                    if (error as NSError).code != 216 {
                        print("[SpeechService] Recognition error: \(error.localizedDescription)")
                    }
                }

                if result?.isFinal == true {
                    self?.isRecording = false
                }
            }
        }

        isRecording = true
        currentTranscription = ""
        lastSpeechTime = Date()
        resetSilenceTimer()

        print("[SpeechService] Recording started (on-device: \(prefersOnDevice))")
    }

    func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        silenceTimer?.invalidate()
        silenceTimer = nil

        let wasRecording = isRecording
        isRecording = false

        if wasRecording {
            print("[SpeechService] Recording stopped. Final: \(currentTranscription.prefix(100))")
        }
    }

    // MARK: - VAD (Voice Activity Detection)

    private func processAudioLevel(_ rms: Float) {
        if rms > silenceThreshold {
            lastSpeechTime = Date()
            resetSilenceTimer()
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()

        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Check if enough silence has elapsed since last speech
            if let lastSpeech = self.lastSpeechTime,
               Date().timeIntervalSince(lastSpeech) >= self.silenceTimeout {
                print("[SpeechService] VAD: silence detected for \(self.silenceTimeout)s — auto-stopping")
                self.stopRecording()
            }
        }
    }

    /// Toggle recording on/off
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Get the final transcription and clear it
    func getTranscription() -> String {
        let text = currentTranscription
        return text
    }
}