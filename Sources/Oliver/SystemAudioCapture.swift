import Foundation
import AVFoundation
import CoreAudio
import ScreenCaptureKit

/// Captures system audio (what's playing through the speakers) using ScreenCaptureKit.
/// NOTE: Requires Screen Recording permission (already requested by the app).
@available(macOS 12.3, *)
class SystemAudioCapture: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0.0

    private var audioStream: SCStream?
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Data] = []
    private var sampleRate: Double = 48000
    @Published var lastCapturedWAV: Data?

    /// Start capturing system audio output using ScreenCaptureKit
    func startCapture() {
        guard !isCapturing else { return }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

                let config = SCStreamConfiguration()
                // Audio-only capture — disable video to reduce overhead
                config.capturesAudio = true
                config.sampleRate = 48000
                config.channelCount = 2
                config.minimumFrameInterval = .zero

                // Capture all system audio (no filter needed for audio-only)
                guard let display = content.displays.first else {
                    print("[SystemAudio] No displays found")
                    await MainActor.run { self.isCapturing = false }
                    return
                }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))

                try await stream.startCapture()

                self.audioStream = stream
                self.isCapturing = true
                self.audioBuffer.removeAll()
                self.lastCapturedWAV = nil
                self.sampleRate = 48000

                print("[SystemAudio] ScreenCaptureKit capture started at \(self.sampleRate)Hz")
            } catch {
                print("[SystemAudio] Failed to start ScreenCaptureKit: \(error)")
                await MainActor.run {
                    self.isCapturing = false
                }
            }
        }
    }

    /// Stop capturing and save the WAV data for later transcription
    @discardableResult
    func stopCapture() -> Data? {
        guard isCapturing else { return nil }

        isCapturing = false

        if let stream = audioStream {
            stream.stopCapture { error in
                if let error = error {
                    print("[SystemAudio] Stop capture error: \(error)")
                }
            }
            audioStream = nil
        }

        // Export WAV before clearing buffer
        lastCapturedWAV = exportWAV()

        let data = audioBuffer.isEmpty ? nil : audioBuffer.reduce(Data()) { $0 + $1 }
        audioBuffer.removeAll()
        print("[SystemAudio] Capture stopped, WAV: \(lastCapturedWAV?.count ?? 0) bytes")
        return data
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }

        // Calculate audio level
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            if let asbd = asbd {
                self.sampleRate = asbd.pointee.mSampleRate
            }
        }

        // Calculate RMS from sample buffer
        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if status == kCMBlockBufferNoErr, let ptr = dataPointer {
                let frameCount = length / MemoryLayout<Float32>.size
                if frameCount > 0 {
                    let floatPtr = UnsafeRawPointer(ptr).bindMemory(to: Float32.self, capacity: frameCount)
                    var sum: Float = 0
                    for i in 0..<frameCount {
                        sum += floatPtr[i] * floatPtr[i]
                    }
                    let rms = sqrtf(sum / Float(frameCount))

                    DispatchQueue.main.async { [weak self] in
                        self?.audioLevel = rms
                    }

                    // Store raw audio data
                    let data = Data(bytes: ptr, count: length)
                    audioBuffer.append(data)
                }
            }
        }
    }
}

// MARK: - Fallback for older macOS (not used — Package.swift requires macOS 13+)

extension SystemAudioCapture {
    /// Export captured audio as WAV data (for transcription APIs)
    func exportWAV() -> Data? {
        guard !audioBuffer.isEmpty else {
            return lastCapturedWAV
        }

        let totalDataSize = audioBuffer.reduce(0) { $0 + $1.count }
        let header = WAVHeader(
            sampleRate: UInt32(sampleRate),
            channels: 2,
            bitsPerSample: 32,
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
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) })  // IEEE float
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
