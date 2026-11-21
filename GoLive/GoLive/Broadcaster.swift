import AVFoundation
import QuartzCore
import HaishinKit
import RTMPHaishinKit
import SwiftUI
import VideoToolbox

/// Camera + microphone capture and the RTMP push to YouTube.
@MainActor
final class Broadcaster {
    let mixer = MediaMixer()
    private var connection: RTMPConnection?
    private var stream: RTMPStream?
    private var statusTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var gate: SyncGate?
    private(set) var isFront = false
    private var stabilization: Stabilization = .off

    /// Called when the RTMP connection drops without us asking it to.
    var onDisconnect: (() -> Void)?

    func startCapture(front: Bool, quality: Quality, stabilization: Stabilization) async throws {
        self.stabilization = stabilization
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        try audioSession.setActive(true)

        await mixer.setSessionPreset(quality.preset)
        await mixer.setVideoOrientation(.portrait)
        await setMuted(false)
        try await attachCamera(front: front)
        try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
        await mixer.startRunning()
        diag("capture running: preset \(quality.label), stabilization setting \(stabilization.rawValue), active mode \(await activeStabilizationDescription())")
    }

    /// What the capture connection is really doing, after the session settled.
    private func activeStabilizationDescription() async -> String {
        final class Box: @unchecked Sendable { var value = "unknown" }
        let box = Box()
        try? await mixer.configuration(video: 0) { unit in
            guard let connection = unit.output?.connections.first else {
                box.value = "no connection"
                return
            }
            box.value = Self.describe(connection.activeVideoStabilizationMode) + " (asked \(Self.describe(connection.preferredVideoStabilizationMode)))"
        }
        return box.value
    }

    nonisolated static func describe(_ mode: AVCaptureVideoStabilizationMode) -> String {
        switch mode {
        case .off: return "off"
        case .standard: return "standard"
        case .cinematic: return "cinematic"
        case .cinematicExtended: return "cinematicExtended"
        case .previewOptimized: return "previewOptimized"
        case .auto: return "auto"
        default:
            if #available(iOS 18.0, *), mode == .cinematicExtendedEnhanced { return "cinematicExtendedEnhanced" }
            if #available(iOS 26.0, *), mode == .lowLatency { return "lowLatency" }
            return "mode \(mode.rawValue)"
        }
    }

    func stopCapture() async {
        await mixer.setTorchEnabled(false)
        await mixer.stopRunning()
        try? await mixer.attachVideo(nil, track: 0)
        try? await mixer.attachAudio(nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func publish(url: String, key: String, orientation: AVCaptureVideoOrientation, quality: Quality) async throws {
        await unpublish()
        await mixer.setVideoOrientation(orientation)

        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)

        let portrait = orientation == .portrait
        var video = await stream.videoSettings
        video.videoSize = portrait
            ? CGSize(width: quality.shortSide, height: quality.longSide)
            : CGSize(width: quality.longSide, height: quality.shortSide)
        video.bitRate = quality.bitrate
        video.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String
        video.maxKeyFrameIntervalDuration = 2
        video.expectedFrameRate = 30
        try await stream.setVideoSettings(video)

        var audio = await stream.audioSettings
        audio.bitRate = 128_000
        try await stream.setAudioSettings(audio)

        await stream.setBitRateStrategy(StreamVideoAdaptiveBitRateStrategy(mamimumVideoBitrate: quality.bitrate))
        // The gate sits between the camera and the stream so audio and video start in sync
        // even when stabilization holds frames back.
        let gate = SyncGate(stream: stream)
        await mixer.addOutput(gate)
        self.gate = gate
        self.connection = connection
        self.stream = stream

        diag("rtmp connecting to \(url) (\(portrait ? "portrait" : "landscape") \(video.videoSize.width)x\(video.videoSize.height) @ \(video.bitRate / 1000) kbps)")
        let connected = try await connection.connect(url)
        diag("rtmp connected: \(connected.status?.code ?? "no status") \(connected.status?.description ?? "")")
        let primed = await gate.primeStream()
        diag("stream header: \(primed)")
        let published = try await stream.publish(key)
        diag("rtmp publishing: \(published.status?.code ?? "no status") \(published.status?.description ?? "")")
        gate.arm()

        statusTask = Task { [weak self] in
            for await status in await connection.status {
                if Task.isCancelled { return }
                diag("rtmp status: \(status.code) \(status.description)")
                if status.code == RTMPConnection.Code.connectClosed.rawValue || status.level == "error" {
                    self?.onDisconnect?()
                    return
                }
            }
        }
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, let stream = self.stream, let gate = self.gate else { return }
                let fps = await stream.currentFPS
                let bytes = await stream.info.byteCount
                let state = await stream.readyState
                diag("stats: \(gate.counts) | encoder \(fps) fps, \(bytes / 1024) KB sent, stream \(state)")
            }
        }
    }

    func unpublish() async {
        statusTask?.cancel()
        statusTask = nil
        statsTask?.cancel()
        statsTask = nil
        if let gate {
            await mixer.removeOutput(gate)
        }
        gate = nil
        if let stream {
            _ = try? await stream.close()
        }
        if let connection {
            try? await connection.close()
        }
        stream = nil
        connection = nil
    }

    func flip() async {
        try? await attachCamera(front: !isFront)
    }

    func setMuted(_ muted: Bool) async {
        var settings = await mixer.audioMixerSettings
        settings.isMuted = muted
        await mixer.setAudioMixerSettings(settings)
    }

    func setTorch(_ on: Bool) async {
        await mixer.setTorchEnabled(on)
    }

    private func attachCamera(front: Bool) async throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back) else {
            throw AppError("No camera available.")
        }
        // Best guess from the camera's current format, applied as the camera attaches so a
        // flip mid-stream never runs unstabilized...
        let guess = stabilization.bestMode(for: device)
        try await mixer.attachVideo(device, track: 0) { unit in
            unit.preferredVideoStabilizationMode = guess
        }
        isFront = front
        // ...then corrected once the session preset has settled the format, only if it changed,
        // since changing it on a running session reconfigures the capture pipeline.
        let mode = stabilization.bestMode(for: device)
        if mode != guess {
            try? await mixer.configuration(video: 0) { unit in
                unit.preferredVideoStabilizationMode = mode
            }
        }
    }
}

/// Forwards camera and microphone to the stream, dropping the video frames captured before
/// the stream's first audio sample.
///
/// The stream zeroes audio and video timestamps independently at the first sample of each.
/// Stabilization delivers each frame late but stamped with its capture time, so without this
/// the first video frame would be older than the first audio sample and the whole broadcast
/// would play with the picture behind the sound by the stabilizer's delay.
final class SyncGate: MediaMixerOutput, @unchecked Sendable {
    /// Never hold video back longer than this, whatever the timestamps say.
    private static let maxHold: TimeInterval = 2.5
    /// If no audio shows up this soon after arming (e.g. the mic is suspended by a phone call),
    /// stop waiting for it: losing sync is better than losing footage.
    private static let audioGrace: TimeInterval = 0.3

    private let stream: RTMPStream
    private let lock = NSLock()
    private var armedAt: TimeInterval?
    private var firstAudio: TimeInterval?
    private var open = false
    private var videoIn = 0, videoOut = 0, audioIn = 0, audioOut = 0
    // The newest samples seen before publishing, kept only to show the stream its formats.
    private var primed = false
    private var latestVideo: CMSampleBuffer?
    private var latestAudio: (buffer: AVAudioPCMBuffer, when: AVAudioTime)?

    var counts: String {
        lock.lock()
        defer { lock.unlock() }
        return "video in \(videoIn) out \(videoOut), audio in \(audioIn) out \(audioOut), gate \(open ? "open" : "closed")"
    }

    let videoTrackId: UInt8? = UInt8.max
    let audioTrackId: UInt8? = UInt8.max

    init(stream: RTMPStream) {
        self.stream = stream
    }

    /// Shows the stream one video frame and one audio buffer before it publishes.
    ///
    /// The stream describes itself to YouTube (resolution, codec, frame rate, audio format) in the
    /// header it sends when publishing, built from the formats of samples it has already seen.
    /// Its encoders aren't running yet, so these two samples are only inspected, never sent; and
    /// this is awaited before publish, so it can't overlap the encoders starting.
    /// Returns a short description for the diagnostics log.
    func primeStream() async -> String {
        // Both are normally already here. Give the camera up to half a second, but the mic only
        // a moment: if it's cut off (a phone call), waiting on it would only delay reconnects.
        var tries = 0
        while true {
            let (hasVideo, hasAudio) = primingSamplesPresent
            if (hasVideo || tries >= 25) && (hasAudio || tries >= 5) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
            tries += 1
        }
        let (video, audio) = takePrimingSamples()
        if let video {
            await stream.append(video)
        }
        if let audio {
            await stream.append(audio.buffer, when: audio.when)
        }
        switch (video != nil, audio != nil) {
        case (true, true): return "video and audio formats included"
        case (true, false): return "video format only (no audio yet)"
        case (false, true): return "audio format only (no video yet)"
        case (false, false): return "empty (no samples yet)"
        }
    }

    private var primingSamplesPresent: (video: Bool, audio: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (latestVideo != nil, latestAudio != nil)
    }

    private func takePrimingSamples() -> (CMSampleBuffer?, (buffer: AVAudioPCMBuffer, when: AVAudioTime)?) {
        lock.lock()
        defer { lock.unlock() }
        primed = true
        let samples = (latestVideo, latestAudio)
        latestVideo = nil
        latestAudio = nil
        return samples
    }

    /// Call once the stream is publishing. Nothing reaches the stream before this: the stream's
    /// encoders start inside publish, and a stray early sample would set its timestamp zero.
    func arm() {
        lock.lock()
        armedAt = CACurrentMediaTime()
        firstAudio = nil
        open = false
        lock.unlock()
    }

    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}

    func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        lock.lock()
        audioIn += 1
        guard armedAt != nil else {
            if !primed { latestAudio = (buffer, when) }
            lock.unlock()
            return
        }
        if firstAudio == nil {
            firstAudio = AVAudioTime.seconds(forHostTime: when.hostTime)
            diag("gate: first audio at \(String(format: "%.3f", firstAudio ?? 0)), now \(String(format: "%.3f", CACurrentMediaTime()))")
        }
        audioOut += 1
        lock.unlock()
        let stream = stream
        Task { await stream.append(buffer, when: when) }
    }

    func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        guard shouldPass(sampleBuffer) else { return }
        let stream = stream
        Task { await stream.append(sampleBuffer) }
    }

    private func shouldPass(_ sampleBuffer: CMSampleBuffer) -> Bool {
        let captured = sampleBuffer.presentationTimeStamp.seconds
        lock.lock()
        defer { lock.unlock() }
        videoIn += 1
        if open { videoOut += 1; return true }
        guard let armedAt else {
            if !primed { latestVideo = sampleBuffer }
            return false
        }
        let waited = CACurrentMediaTime() - armedAt
        guard let firstAudio else {
            if waited > Self.audioGrace {
                open = true
                videoOut += 1
                diag("gate: opened after \(String(format: "%.2f", waited)) s with no audio; dropped \(videoIn - videoOut) frames")
                return true
            }
            return false
        }
        if captured >= firstAudio || !captured.isFinite || waited > Self.maxHold {
            open = true
            videoOut += 1
            diag("gate: opened after \(String(format: "%.2f", waited)) s (frame \(String(format: "%.3f", captured)) vs audio \(String(format: "%.3f", firstAudio))); dropped \(videoIn - videoOut) frames")
            return true
        }
        return false
    }
}

/// Live camera preview fed straight from the mixer.
struct CameraPreview: UIViewRepresentable {
    let mixer: MediaMixer

    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: .zero)
        view.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        let mixer = mixer
        Task { await mixer.addOutput(view) }
        return view
    }

    func updateUIView(_ uiView: MTHKView, context: Context) {}
}
