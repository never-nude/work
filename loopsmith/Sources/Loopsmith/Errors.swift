import Foundation

enum LoopsmithError: LocalizedError {
    case noVideoTrack
    case gifCreateFailed
    case gifFinalizeFailed
    case noFrames
    case notRecording
    case screenPermission(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "That file has no video track."
        case .gifCreateFailed:
            return "Couldn't create the GIF file."
        case .gifFinalizeFailed:
            return "Couldn't finish writing the GIF."
        case .noFrames:
            return "No frames could be read from the selected range."
        case .notRecording:
            return "No recording is in progress."
        case .screenPermission(let detail):
            return "Screen recording isn't available. Grant Loopsmith access in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. (\(detail))"
        }
    }
}
