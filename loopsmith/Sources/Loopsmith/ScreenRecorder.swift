import AppKit
import AVFoundation
import ScreenCaptureKit

enum CaptureTarget: Identifiable {
    case display(SCDisplay)
    case window(SCWindow)

    var id: String {
        switch self {
        case .display(let display):
            return "display-\(display.displayID)"
        case .window(let window):
            return "window-\(window.windowID)"
        }
    }

    var title: String {
        switch self {
        case .display(let display):
            return "Display \(display.displayID) — \(display.width) × \(display.height)"
        case .window(let window):
            let app = window.owningApplication?.applicationName ?? "App"
            let name = window.title ?? "Untitled"
            return "\(app) — \(name)"
        }
    }

    var isDisplay: Bool {
        if case .display = self { return true }
        return false
    }
}

/// Records a display or a single window to a temporary .mov using ScreenCaptureKit.
final class ScreenRecorder: NSObject, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private(set) var outputURL: URL?

    private let lock = NSLock()
    private var finishContinuation: CheckedContinuation<Void, Error>?

    static func availableTargets() async throws -> [CaptureTarget] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw LoopsmithError.screenPermission(error.localizedDescription)
        }

        let ownBundle = Bundle.main.bundleIdentifier
        var targets: [CaptureTarget] = content.displays.map { .display($0) }

        let windows = content.windows.filter { window in
            guard let app = window.owningApplication else { return false }
            if let ownBundle, app.bundleIdentifier == ownBundle { return false }
            guard window.windowLayer == 0 else { return false }
            guard window.frame.width >= 200, window.frame.height >= 120 else { return false }
            return !(window.title ?? "").isEmpty
        }
        targets += windows.map { .window($0) }
        return targets
    }

    func start(target: CaptureTarget, fps: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Loopsmith-\(Int(Date().timeIntervalSince1970)).mov")
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter

        switch target {
        case .display(let display):
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
        }

        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.queueDepth = 5

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = url
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()

        self.stream = stream
        self.output = recordingOutput
        self.outputURL = url
        return url
    }

    func stop() async throws -> URL {
        guard let stream, let url = outputURL else {
            throw LoopsmithError.notRecording
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            finishContinuation = continuation
            lock.unlock()

            Task {
                do {
                    try await stream.stopCapture()
                    // The delegate normally finishes first. If it never does, give the writer a
                    // moment and accept the file as-is.
                    try? await Task.sleep(for: .seconds(2))
                    self.resume(.success(()))
                } catch {
                    self.resume(.failure(error))
                }
            }
        }

        self.stream = nil
        self.output = nil
        return url
    }

    private func resume(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = finishContinuation
        finishContinuation = nil
        lock.unlock()
        guard let continuation else { return }
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    // MARK: SCRecordingOutputDelegate

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        resume(.success(()))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        resume(.failure(error))
    }
}
