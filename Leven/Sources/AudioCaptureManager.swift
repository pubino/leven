import AVFoundation
import ScreenCaptureKit
import os.log

private let logger = Logger(subsystem: "com.leven.app", category: "AudioCapture")

enum CaptureState: Equatable {
    case idle
    case recording
    case stopped
    case saving
    case error(String)
}

/// Manages audio capture from a specific application using ScreenCaptureKit.
@MainActor
final class AudioCaptureManager: NSObject, ObservableObject {
    @Published var state: CaptureState = .idle
    @Published var duration: TimeInterval = 0

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var startTime: Date?
    private var durationTimer: Timer?
    private var streamDelegate: StreamDelegate?
    private var outputHandler: CaptureOutputHandler?

    /// Start capturing audio from the application with the given PID.
    func startCapture(pid: pid_t) async {
        guard state == .idle || state == .stopped || state.isError else { return }

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            state = .error("Screen recording permission is required. Grant access in System Settings > Privacy & Security > Screen & System Audio Recording, then try again.")
            return
        }

        do {
            // Get shareable content and find the target app
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )

            guard content.applications.contains(where: { $0.processID == pid }) else {
                state = .error("Application not found. Grant screen recording permission in System Settings > Privacy & Security > Screen & System Audio Recording.")
                return
            }

            guard let display = content.displays.first else {
                state = .error("No display found.")
                return
            }

            // Create a filter that captures only the target app's audio.
            let excludedApps = content.applications.filter { $0.processID != pid }
            let appFilter = SCContentFilter(
                display: display,
                excludingApplications: excludedApps,
                exceptingWindows: []
            )

            // Configure for audio-only capture (small dummy video required by SCStream)
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            // Prepare the file writer
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "leven_capture_\(Int(Date().timeIntervalSince1970)).m4a"
            let url = tempDir.appendingPathComponent(fileName)
            outputURL = url

            let writer = try AVAssetWriter(url: url, fileType: .m4a)
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)

            guard writer.startWriting() else {
                state = .error("Failed to start writer: \(writer.error?.localizedDescription ?? "unknown error")")
                return
            }
            // Don't start the session yet — we'll start it at the first audio sample's timestamp

            self.assetWriter = writer
            self.audioInput = input

            // Create and start the stream
            let delegate = StreamDelegate { [weak self] error in
                Task { @MainActor [weak self] in
                    await self?.handleStreamError(error)
                }
            }
            self.streamDelegate = delegate
            let captureStream = SCStream(filter: appFilter, configuration: config, delegate: delegate)

            let handler = CaptureOutputHandler(audioInput: input, assetWriter: writer)
            self.outputHandler = handler

            let captureQueue = DispatchQueue(label: "com.leven.capture", qos: .userInitiated)

            // Register both screen and audio output handlers.
            // Some macOS versions require a screen handler for audio delivery to work.
            try captureStream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: captureQueue)
            try captureStream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: captureQueue)

            try await captureStream.startCapture()
            self.stream = captureStream

            logger.info("Capture started for PID \(pid)")

            startTime = Date()
            state = .recording
            startDurationTimer()

        } catch {
            logger.error("startCapture failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    /// Handle stream stopping unexpectedly (e.g., target app quit).
    private func handleStreamError(_ error: Error) async {
        guard state == .recording else { return }

        stopDurationTimer()
        stream = nil

        let samplesWritten = outputHandler?.samplesWritten ?? 0
        logger.warning("Stream error after \(samplesWritten) samples: \(error.localizedDescription)")

        audioInput?.markAsFinished()
        await assetWriter?.finishWriting()

        state = .error("Recording stopped: \(error.localizedDescription)")
        duration = 0
    }

    /// Stop the current capture.
    func stopCapture() async {
        guard state == .recording else { return }

        stopDurationTimer()

        do {
            try await stream?.stopCapture()
        } catch {
            // Stream may already be stopped
        }
        stream = nil

        let samplesWritten = outputHandler?.samplesWritten ?? 0
        logger.info("Capture stopped. Audio samples written: \(samplesWritten)")

        audioInput?.markAsFinished()
        await assetWriter?.finishWriting()

        if samplesWritten == 0 {
            state = .error("No audio was captured. Make sure the app is producing audio and screen recording permission is granted.")
        } else {
            state = .stopped
        }
        duration = 0
    }

    /// Save the last recorded audio to a user-chosen location.
    func saveRecording() async -> Bool {
        guard let sourceURL = outputURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            state = .error("No recording to save.")
            return false
        }

        guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
            state = .error("No window available for save dialog.")
            return false
        }

        state = .saving

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = "recording.m4a"
        panel.canCreateDirectories = true

        let response = await panel.beginSheetModal(for: window)

        if response == .OK, let destURL = panel.url {
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                state = .idle
                outputURL = nil
                return true
            } catch {
                state = .error("Failed to save: \(error.localizedDescription)")
                return false
            }
        }

        state = .stopped
        return false
    }

    var hasRecording: Bool {
        guard let url = outputURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.startTime else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

extension CaptureState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Stream Delegate

private class StreamDelegate: NSObject, SCStreamDelegate {
    let onError: (Error) -> Void

    init(onError: @escaping (Error) -> Void) {
        self.onError = onError
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onError(error)
    }
}

// MARK: - Capture Output Handler

/// Handles both screen and audio output from SCStream.
/// Screen frames are discarded; audio samples are written to the AVAssetWriter.
private class CaptureOutputHandler: NSObject, SCStreamOutput {
    let audioInput: AVAssetWriterInput
    let assetWriter: AVAssetWriter
    private var sessionStarted = false
    private(set) var samplesWritten: Int = 0

    init(audioInput: AVAssetWriterInput, assetWriter: AVAssetWriter) {
        self.audioInput = audioInput
        self.assetWriter = assetWriter
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        // Discard video frames — we only care about audio
        guard type == .audio else { return }
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard sampleBuffer.numSamples > 0 else { return }

        // Start the writer session at the first audio sample's timestamp
        if !sessionStarted {
            let startTime = sampleBuffer.presentationTimeStamp
            assetWriter.startSession(atSourceTime: startTime)
            sessionStarted = true
            logger.info("Writer session started at \(startTime.seconds)s")
        }

        if audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
            samplesWritten += 1
        } else {
            logger.debug("Writer not ready, dropped audio buffer")
        }
    }
}
