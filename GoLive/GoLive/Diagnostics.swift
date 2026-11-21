import Foundation
import SwiftUI
import UIKit

/// A short, shareable record of what happened during the last run.
/// Every line is also printed, so `./run.sh --console` shows it live.
final class Diag: @unchecked Sendable {
    static let shared = Diag()

    private let lock = NSLock()
    private var lines: [String] = []
    private let limit = 400
    private let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func log(_ message: String) {
        let line = "\(clock.string(from: Date())) \(message)"
        print("[GoLive] \(line)")
        lock.lock()
        lines.append(line)
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        let device = UIDevice.current
        let header = "GoLive diagnostics · \(device.model) iOS \(device.systemVersion)\n"
        return header + lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }
}

func diag(_ message: String) {
    Diag.shared.log(message)
}

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = Diag.shared.text

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
            .onAppear { text = Diag.shared.text }
        }
    }
}
