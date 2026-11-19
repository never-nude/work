import AVFoundation
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
    private(set) var isFront = false

    /// Called when the RTMP connection drops without us asking it to.
    var onDisconnect: (() -> Void)?

    func startCapture(front: Bool, quality: Quality) async throws {
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
        await mixer.addOutput(stream)
        self.connection = connection
        self.stream = stream

        _ = try await connection.connect(url)
        _ = try await stream.publish(key)

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
        if let stream {
            _ = try? await stream.close()
            await mixer.removeOutput(stream)
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
        try await mixer.attachVideo(device, track: 0)
        isFront = front
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
