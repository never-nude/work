import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

/// Single source of truth for the editor: the loaded clip, trim range, export settings,
/// screen-recording state, and the preview player.
@MainActor
@Observable
final class Studio {
    struct ExportResult: Identifiable {
        let id = UUID()
        let url: URL
        let bytes: Int
        let frames: Int
    }

    // Source
    var sourceURL: URL?
    var asset: AVAsset?
    var duration: Double = 0
    var naturalSize: CGSize = .zero

    // Trim + playback
    var start: Double = 0
    var end: Double = 0
    var currentTime: Double = 0
    let player = AVPlayer()

    // Export settings
    var fps: Int = 15
    var width: Int = 480
    var speed: Double = 1
    var boomerang = false

    // Export state
    var isExporting = false
    var exportProgress: Double = 0
    var lastExport: ExportResult?

    // Screen recording
    var showRecorder = false
    var isRecording = false
    var captureTargets: [CaptureTarget] = []
    var selectedTargetID: String?
    var recordingFPS: Int = 30

    var errorMessage: String?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private let recorder = ScreenRecorder()

    static let fpsOptions = [10, 12, 15, 20, 24, 30]
    static let speedOptions: [Double] = [0.5, 1, 1.5, 2, 3]

    init() {
        player.isMuted = true
        player.actionAtItemEnd = .none
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.tick(time.seconds)
            }
        }
    }

    // MARK: Derived values

    var widthOptions: [Int] {
        let natural = Int(naturalSize.width.rounded())
        guard natural > 0 else { return [320, 480, 640, 800] }
        var options = [240, 320, 480, 640, 800, 1024].filter { $0 < natural }
        options.append(natural)
        return options
    }

    var outputHeight: Int {
        guard naturalSize.width > 0 else { return 0 }
        return Int((Double(width) * naturalSize.height / naturalSize.width).rounded())
    }

    var selectionLength: Double { max(0, end - start) }

    var settings: GifSettings {
        GifSettings(
            start: start, end: end, fps: fps, width: width, height: max(outputHeight, 1),
            speed: speed, boomerang: boomerang
        )
    }

    var estimatedFrames: Int { settings.frameCount }

    // MARK: Loading

    func openVideoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to turn into a GIF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await load(url: url) }
    }

    func load(url: URL) async {
        let newAsset = AVURLAsset(url: url)
        do {
            let loadedDuration = try await newAsset.load(.duration)
            guard let track = try await newAsset.loadTracks(withMediaType: .video).first else {
                throw LoopsmithError.noVideoTrack
            }
            let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(transform)

            player.pause()
            naturalSize = CGSize(width: abs(rect.width), height: abs(rect.height))
            duration = loadedDuration.seconds
            start = 0
            end = min(duration, 5)
            currentTime = 0
            sourceURL = url
            asset = newAsset
            lastExport = nil
            if !widthOptions.contains(width) {
                width = widthOptions.contains(480) ? 480 : widthOptions[0]
            }

            player.replaceCurrentItem(with: AVPlayerItem(asset: newAsset))
            seek(to: 0)
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        asset = nil
        sourceURL = nil
        duration = 0
        start = 0
        end = 0
        currentTime = 0
        lastExport = nil
    }

    // MARK: Playback

    private func tick(_ seconds: Double) {
        currentTime = seconds
        guard end > start, player.rate != 0 else { return }
        if seconds >= end - 0.02 {
            seek(to: start)
        }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Pause and jump to a time; used while dragging trim handles.
    func scrub(to seconds: Double) {
        player.pause()
        seek(to: seconds)
    }

    func playSelection() {
        seek(to: start)
        player.play()
    }

    func togglePlayback() {
        if player.rate == 0 {
            if currentTime < start || currentTime >= end - 0.02 {
                seek(to: start)
            }
            player.play()
        } else {
            player.pause()
        }
    }

    func setInPoint() {
        start = min(currentTime, end - 0.1)
    }

    func setOutPoint() {
        end = max(currentTime, start + 0.1)
    }

    // MARK: Export

    func exportPanel() {
        guard asset != nil, let sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + ".gif"
        panel.message = "Save the GIF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await export(to: url) }
    }

    func export(to url: URL) async {
        guard let asset else { return }
        player.pause()
        isExporting = true
        exportProgress = 0
        lastExport = nil
        defer { isExporting = false }

        do {
            let frames = try await GifExporter.export(asset: asset, settings: settings, to: url) { value in
                Task { @MainActor in
                    self.exportProgress = value
                }
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            lastExport = ExportResult(url: url, bytes: bytes, frames: frames)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Screen recording

    func refreshTargets() async {
        do {
            captureTargets = try await ScreenRecorder.availableTargets()
            if selectedTargetID == nil || !captureTargets.contains(where: { $0.id == selectedTargetID }) {
                selectedTargetID = captureTargets.first?.id
            }
        } catch {
            captureTargets = []
            errorMessage = error.localizedDescription
        }
    }

    func startRecording() async {
        guard let target = captureTargets.first(where: { $0.id == selectedTargetID }) else { return }
        do {
            _ = try await recorder.start(target: target, fps: recordingFPS)
            isRecording = true
            showRecorder = false
            setWindowFloating(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        do {
            let url = try await recorder.stop()
            isRecording = false
            setWindowFloating(false)
            await load(url: url)
        } catch {
            isRecording = false
            setWindowFloating(false)
            errorMessage = error.localizedDescription
        }
    }

    private func setWindowFloating(_ floating: Bool) {
        for window in NSApp.windows where window.isVisible {
            window.level = floating ? .floating : .normal
        }
    }
}

// MARK: - Formatting helpers

enum TimeFormat {
    static func clock(_ seconds: Double) -> String {
        let safe = max(0, seconds)
        let minutes = Int(safe) / 60
        let remainder = safe - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, remainder)
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
