import CullCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.scan()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                .help("Scan again (⌘R)")
            }
        }
        .confirmationDialog(model.confirmationTitle, isPresented: $model.showingConfirmation, titleVisibility: .visible) {
            Button("Cull \(Format.bytes(model.selectedBytes))", role: .destructive) { model.confirmCull() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.confirmationMessage)
        }
        .task {
            model.start()
            if Snapshot.showsSettings { openSettings() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .failed(let message):
            MessageView(symbol: "exclamationmark.triangle", title: "Cull can't run here", detail: message)
        case .culling:
            CullingView(progress: model.cullProgress)
        case .starting, .scanning:
            ScanningView(progress: model.scanProgress)
        case .ready:
            if let report = model.report {
                ResultsView(report: report)
            } else {
                ScanningView(progress: nil)
            }
        }
    }
}

// MARK: Header

struct HeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            DiskPanel()
            Spacer(minLength: 12)
            SelectionPanel()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct DiskPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.secondary)
                Text(model.volumeName)
                    .font(.headline)
                if let disk = model.disk, let label = disk.pressure.label {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.color(for: disk.pressure), in: Capsule())
                }
            }
            if let disk = model.disk {
                DiskBar(disk: disk, freeing: model.phase == .ready ? model.selectedBytesFreedNow : 0)
                    .frame(height: 10)
                Text(caption(for: disk))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    private func caption(for disk: DiskSpace) -> String {
        var text = Format.disk(disk)
        let freeing = model.phase == .ready ? model.selectedBytesFreedNow : 0
        if freeing > 0 {
            text += "  →  \(Format.bytes(disk.available + freeing)) after culling"
        }
        return text
    }
}

/// The disk as a block of material: grey is what is in use, terracotta is what the
/// current selection would carve away, and the pale track is free space.
struct DiskBar: View {
    let disk: DiskSpace
    let freeing: Int64

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let used = max(width * disk.usedFraction, 6)
            let share = disk.total > 0 ? Double(freeing) / Double(disk.total) : 0
            let cut = freeing > 0 ? min(used, max(width * share, 3)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Rectangle()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: used)
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: cut)
                    .offset(x: used - cut)
            }
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.25), value: freeing)
        }
        .accessibilityElement()
        .accessibilityLabel("Disk usage")
        .accessibilityValue("\(Format.percent(disk.usedFraction)) used")
    }
}

private struct SelectionPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(model.selectedBytes))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: model.selectedBytes)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                model.requestCull()
            } label: {
                Text("Cull")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canCull)
            .help("Remove what is selected (⌘↩)")
        }
        .opacity(model.report == nil ? 0.35 : 1)
    }

    private var subtitle: String {
        guard let report = model.report else { return "selected" }
        return "selected of \(Format.bytes(report.totalBytes)) found"
    }
}

// MARK: States

struct ScanningView: View {
    let progress: ScanProgress?

    var body: some View {
        VStack(spacing: 12) {
            if let progress, progress.phase == .measuring, progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .frame(width: 300)
                Text("Weighing \(progress.completed) of \(progress.total)")
                    .font(.headline)
                    .monospacedDigit()
                Text(progress.current.isEmpty ? " " : progress.current)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Looking around…")
                    .font(.headline)
            }
        }
        .padding(40)
    }
}

struct CullingView: View {
    let progress: CullProgress?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress?.fraction ?? 0)
                .frame(width: 300)
            Text("Culled \(Format.bytes(progress?.bytesSoFar ?? 0)) so far")
                .font(.headline)
                .monospacedDigit()
            Text((progress?.current.isEmpty ?? true) ? " " : (progress?.current ?? ""))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
        }
        .padding(40)
    }
}

struct MessageView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
    }
}
