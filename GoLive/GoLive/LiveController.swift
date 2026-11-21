import AVFoundation
import SwiftUI
import UIKit

/// Owns the whole "press button, be live" sequence and its teardown.
@MainActor
final class LiveController: ObservableObject {
    static let shared = LiveController()

    enum Phase: Equatable {
        case idle
        case starting(String)
        case live
        case ending
        case ended(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var title = ""
    @Published private(set) var startedAt: Date?
    @Published private(set) var watchURL: URL?
    @Published private(set) var isMuted = false
    @Published private(set) var isFront = false
    @Published private(set) var isTorchOn = false
    @Published private(set) var isReconnecting = false
    /// Degrees the on-screen controls are turned so they read upright when the phone is held sideways.
    @Published private(set) var uiRotation: Double = 0

    let broadcaster = Broadcaster()

    private let settings = AppSettings.shared
    private let auth = GoogleAuth.shared
    private var runTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var broadcastID: String?
    private var number: Int?
    private var sawLive = false
    private var publishTarget: (url: String, key: String, orientation: AVCaptureVideoOrientation)?
    private var pendingAutoStart = true

    private init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        broadcaster.onDisconnect = { [weak self] in self?.handleDisconnect() }
    }

    var isBusy: Bool {
        switch phase {
        case .starting, .live: return true
        default: return false
        }
    }

    var showsCamera: Bool { isBusy || phase == .ending }

    // MARK: App lifecycle

    func appBecameActive() {
        guard pendingAutoStart else { return }
        pendingAutoStart = false
        if settings.goLiveOnOpen { start() }
    }

    func appDidBackground() {
        pendingAutoStart = true
        // iOS takes the camera away in the background, so the stream ends with the app.
        stop()
    }

    // MARK: Start

    func start() {
        guard auth.isSignedIn, !isBusy, phase != .ending else { return }
        runTask = Task { await run() }
    }

    private func api() async throws -> YouTubeAPI {
        YouTubeAPI(token: try await auth.validToken())
    }

    private func step(_ message: String) throws {
        try Task.checkCancellation()
        diag("step: \(message)")
        phase = .starting(message)
    }

    private func run() async {
        broadcastID = nil
        number = nil
        sawLive = false
        publishTarget = nil
        startedAt = nil
        watchURL = nil
        isMuted = false
        isTorchOn = false
        isReconnecting = false
        uiRotation = 0
        isFront = settings.useFrontCamera
        title = "Live stream \(settings.nextNumber)"
        Diag.shared.clear()
        diag("start: \(title), \(settings.privacy.rawValue), \(settings.quality.label), stabilization \(settings.stabilization.rawValue), front \(settings.useFrontCamera)")
        phase = .starting("Waking the camera")
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            let camera = await AVCaptureDevice.requestAccess(for: .video)
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            guard camera, microphone else {
                throw AppError("Camera and microphone access are off. Turn them on in Settings → Apps → GoLive.")
            }

            // Camera spin-up and the YouTube calls run side by side.
            async let capture: Void = broadcaster.startCapture(front: settings.useFrontCamera, quality: settings.quality, stabilization: settings.stabilization)

            let api = try await api()
            let n = settings.nextNumber
            title = "Live stream \(n)"
            try step("Creating \(title)")
            let id = try await api.createBroadcast(title: title, privacy: settings.privacy)
            diag("broadcast created \(id)")
            broadcastID = id
            number = n
            settings.nextNumber = n + 1
            watchURL = URL(string: "https://youtu.be/\(id)")

            let ingest = try await boundIngest(api: api, broadcastID: id)
            diag("bound to stream \(ingest.streamID) at \(ingest.url)")
            try await capture

            try step("Connecting to YouTube")
            let orientation = currentVideoOrientation()
            publishTarget = (ingest.url, ingest.key, orientation)
            try await broadcaster.publish(url: ingest.url, key: ingest.key, orientation: orientation, quality: settings.quality)

            try step("Waiting for YouTube")
            try await monitor(broadcastID: id)
        } catch {
            if Task.isCancelled { return }   // stop() owns the teardown
            diag("failed: \(describe(error)) [\(error)]")
            let discarded = await closeOut()
            phase = .failed(describe(error) + (discarded ? "" : "\n\(title) was already created on YouTube."))
        }
    }

    /// Binds the broadcast to the cached ingest point, or makes a fresh one if the cached one is gone.
    private func boundIngest(api: YouTubeAPI, broadcastID: String) async throws -> YouTubeAPI.Ingest {
        if let streamID = settings.streamID, let url = settings.ingestURL, let key = settings.streamKey {
            do {
                try await api.bind(broadcastID: broadcastID, streamID: streamID)
                return .init(streamID: streamID, url: url, key: key)
            } catch is YouTubeAPI.APIError {
                settings.forgetStream()
            }
        }
        let ingest = try await api.createStream()
        settings.streamID = ingest.streamID
        settings.ingestURL = ingest.url
        settings.streamKey = ingest.key
        try await api.bind(broadcastID: broadcastID, streamID: ingest.streamID)
        return ingest
    }

    /// Watches the broadcast until it ends. YouTube flips it live on its own (auto-start);
    /// if that stalls we ask for the transition explicitly.
    private func monitor(broadcastID id: String) async throws {
        let began = Date()
        var lastNudge = Date()
        var polls = 0
        while true {
            try await Task.sleep(nanoseconds: (sawLive ? 30 : 2) * 1_000_000_000)
            let status: String?
            do {
                status = try await api().lifeCycleStatus(broadcastID: id)
            } catch {
                try Task.checkCancellation()
                diag("poll failed: \(error)")
                continue   // a flaky network poll shouldn't kill a healthy stream
            }
            try Task.checkCancellation()
            polls += 1
            if !sawLive, polls % 2 == 0, let streamID = settings.streamID,
               let health = try? await api().streamHealth(streamID: streamID) {
                try Task.checkCancellation()
                diag("youtube: broadcast \(status ?? "gone"), ingest \(health.stream), health \(health.health)")
                if health.stream == "active" {
                    phase = .starting("YouTube has the video, going live")
                } else {
                    phase = .starting("Sending video, YouTube hasn't received it yet")
                }
            } else {
                diag("youtube: broadcast \(status ?? "gone")")
            }
            switch status {
            case "live":
                if !sawLive {
                    diag("LIVE after \(Int(Date().timeIntervalSince(began))) s")
                    sawLive = true
                    startedAt = Date()
                    phase = .live
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            case "complete", "revoked", nil:
                _ = await closeOut()
                phase = .ended("\(title) was ended from YouTube")
                return
            default:
                if sawLive { break }
                if Date().timeIntervalSince(began) > 120 {
                    throw AppError("YouTube never picked up the video. Open Diagnostics from the gear icon to see where it stopped.")
                }
                if Date().timeIntervalSince(lastNudge) > 12 {
                    lastNudge = Date()
                    do {
                        try await api().transition(broadcastID: id, to: "live")
                        diag("asked YouTube to go live")
                    } catch {
                        diag("go-live request refused: \(error)")
                    }
                }
            }
        }
    }

    // MARK: Stop

    func stop() {
        guard isBusy else { return }
        runTask?.cancel()
        reconnectTask?.cancel()
        let elapsed = startedAt.map { Date().timeIntervalSince($0) }
        phase = .ending
        let pending = runTask
        Task {
            let background = UIApplication.shared.beginBackgroundTask(withName: "End live stream")
            await pending?.value
            let discarded = await closeOut()
            if discarded {
                phase = .ended("Cancelled before going live")
            } else if let elapsed {
                phase = .ended("\(title) · \(Self.clock(elapsed))")
            } else {
                phase = .ended("\(title) ended")
            }
            UIApplication.shared.endBackgroundTask(background)
        }
    }

    /// Ends the broadcast on YouTube and releases the camera.
    /// Returns true when the broadcast never aired and was deleted (its number is reused).
    private func closeOut() async -> Bool {
        var discarded = broadcastID == nil
        if let id = broadcastID, let api = try? await api() {
            var status: String? = "live"
            if !sawLive {
                status = (try? await api.lifeCycleStatus(broadcastID: id)) ?? "unknown"
            }
            switch status {
            case "live", "testing", "liveStarting", "testStarting":
                try? await api.transition(broadcastID: id, to: "complete")
            case "ready", "created":
                if (try? await api.deleteBroadcast(id)) != nil {
                    discarded = true
                    if let number, settings.nextNumber == number + 1 { settings.nextNumber = number }
                }
            default:
                break
            }
        }
        broadcastID = nil
        publishTarget = nil
        isReconnecting = false
        await broadcaster.unpublish()
        await broadcaster.stopCapture()
        UIApplication.shared.isIdleTimerDisabled = false
        return discarded
    }

    // MARK: Reconnect

    private func handleDisconnect() {
        guard isBusy, let target = publishTarget, reconnectTask == nil else { return }
        diag("rtmp dropped, reconnecting")
        isReconnecting = true
        reconnectTask = Task {
            defer { reconnectTask = nil }
            for attempt in 1...8 {
                try? await Task.sleep(nanoseconds: UInt64(min(attempt, 4)) * 1_000_000_000)
                if Task.isCancelled || !isBusy { return }
                do {
                    try await broadcaster.publish(url: target.url, key: target.key, orientation: target.orientation, quality: settings.quality)
                    isReconnecting = false
                    return
                } catch {
                    continue
                }
            }
            if Task.isCancelled || !isBusy { return }
            runTask?.cancel()
            let pending = runTask
            phase = .ending
            await pending?.value
            _ = await closeOut()
            phase = .failed("Lost the connection to YouTube and couldn't get it back.")
        }
    }

    // MARK: Controls

    func flipCamera() {
        Task {
            if isTorchOn { await broadcaster.setTorch(false); isTorchOn = false }
            await broadcaster.flip()
            isFront = broadcaster.isFront
        }
    }

    func toggleMute() {
        isMuted.toggle()
        let muted = isMuted
        Task { await broadcaster.setMuted(muted) }
    }

    func toggleTorch() {
        guard !isFront else { return }
        isTorchOn.toggle()
        let on = isTorchOn
        Task { await broadcaster.setTorch(on) }
    }

    func dismissResult() {
        switch phase {
        case .ended, .failed: phase = .idle
        default: break
        }
    }

    // MARK: Helpers

    /// The stream's orientation is fixed at the moment it starts, from how the phone is being held.
    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            uiRotation = 90
            return .landscapeRight
        case .landscapeRight:
            uiRotation = -90
            return .landscapeLeft
        default:
            uiRotation = 0
            return .portrait
        }
    }

    private func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.code == .notConnectedToInternet ? "No internet connection." : urlError.localizedDescription
        }
        if let localized = error as? LocalizedError, let text = localized.errorDescription { return text }
        return "Couldn't go live: \(error)"
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
