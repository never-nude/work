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

        _ = try await connection.connect(url)
        _ = try await stream.publish(key)
        gate.arm()

        statusTask = Task { [weak self] in
            for await status in await connection.status {
                if Task.isCancelled { return }
                if status.code == RTMPConnection.Code.connectClosed.rawValue || status.level == "error" {
                    self?.onDisconnect?()
                    return
                }
            }
        }
    }

    func unpublish() async {
        statusTask?.cancel()
        statusTask = nil
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

    let videoTrackId: UInt8? = UInt8.max
    let audioTrackId: UInt8? = UInt8.max

    init(stream: RTMPStream) {
        self.stream = stream
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
        guard armedAt != nil else {
            lock.unlock()
            return
        }
        if firstAudio == nil {
            firstAudio = AVAudioTime.seconds(forHostTime: when.hostTime)
        }
        lock.unlock()
        let stream = stream
        Task { await stream.append(buffer, when: when) }
    }

    func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        guard shouldPass(sampleBuffer.presentationTimeStamp.seconds) else { return }
        let stream = stream
        Task { await stream.append(sampleBuffer) }
    }

    private func shouldPass(_ captured: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if open { return true }
        guard let armedAt else { return false }
        let waited = CACurrentMediaTime() - armedAt
        guard let firstAudio else {
            if waited > Self.audioGrace {
                open = true
                return true
            }
            return false
        }
        if captured >= firstAudio || !captured.isFinite || waited > Self.maxHold {
            open = true
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
