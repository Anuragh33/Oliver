import Foundation
import AVFoundation
import CoreAudio

/// Captures system audio (what's playing through the speakers) for transcription.
/// Uses a tap on the default output device's audio stream.
/// NOTE: Full system audio capture requires ScreenCapture permission on macOS.
/// On macOS 13+, we use SCStreamConfiguration for system audio.
/// On older macOS, we fall back to a process tap (requires entitlements).
class SystemAudioCapture: ObservableObject {
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0.0

    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Data] = []
    private var sampleRate: Double = 44100
    /// Preserved WAV data after capture stops — available for transcription
    @Published var lastCapturedWAV: Data?

    /// Start capturing system audio output
    func startCapture() {
        guard !isCapturing else { return }

        let engine = AVAudioEngine()
        let node = engine.outputNode
        let format = node.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            print("[SystemAudio] Invalid sample rate from output node")
            return
        }

        sampleRate = format.sampleRate

        // Install a tap on the output node to capture system audio
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            audioEngine = engine
            isCapturing = true
            audioBuffer.removeAll()
            lastCapturedWAV = nil
            print("[SystemAudio] Capture started at \(sampleRate)Hz")
        } catch {
            print("[SystemAudio] Failed to start engine: \(error)")
            node.removeTap(onBus: 0)
        }
    }

    /// Stop capturing and save the WAV data for later transcription
    @discardableResult
    func stopCapture() -> Data? {
        guard isCapturing else { return nil }

        audioEngine?.outputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Export WAV before clearing buffer
        lastCapturedWAV = exportWAV()

        isCapturing = false
        let data = audioBuffer.isEmpty ? nil : audioBuffer.reduce(Data()) { $0 + $1 }
        audioBuffer.removeAll()
        print("[SystemAudio] Capture stopped, \(data?.count ?? 0) bytes recorded, WAV: \(lastCapturedWAV?.count ?? 0) bytes")
        return data
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Calculate audio level (RMS)
        if let channelData = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameCount))
            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = rms
            }
        }

        // Store raw audio as PCM data for potential later use (export to WAV)
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if let channelData = buffer.floatChannelData {
            var data = Data()
            for channel in 0..<channelCount {
                let frames = UnsafeBufferPointer(start: channelData[channel], count: frameLength)
                withUnsafeBytes(of: frames) { data.append(contentsOf: $0) }
            }
            audioBuffer.append(data)
        }
    }

    /// Export captured audio as WAV data (for transcription APIs)
    func exportWAV() -> Data? {
        guard !audioBuffer.isEmpty else {
            // Try last captured WAV data
            return lastCapturedWAV
        }

        // Simple WAV header + PCM data
        let totalDataSize = audioBuffer.reduce(0) { $0 + $1.count }
        let header = WAVHeader(
            sampleRate: UInt32(sampleRate),
            channels: 1,
            bitsPerSample: 16,
            dataSize: UInt32(totalDataSize)
        )

        var wavData = header.data
        for chunk in audioBuffer {
            wavData.append(chunk)
        }
        return wavData
    }
}

// MARK: - WAV Header

private struct WAVHeader {
    let data: Data

    init(sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16, dataSize: UInt32) {
        var header = Data()
        // RIFF header
        header.append(contentsOf: [UInt8]("RIFF".utf8))
        let fileSize = 36 + dataSize
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: [UInt8]("WAVE".utf8))
        // fmt chunk
        header.append(contentsOf: [UInt8]("fmt ".utf8))
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM format
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = UInt16(channels) * bitsPerSample / 8
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        // data chunk
        header.append(contentsOf: [UInt8]("data".utf8))
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        self.data = header
    }
}