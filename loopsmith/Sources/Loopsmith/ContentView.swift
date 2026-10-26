import AppKit
import AVKit
import SwiftUI

struct ContentView: View {
    @Environment(Studio.self) private var studio
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var studio = studio

        Group {
            if studio.asset == nil {
                EmptyStateView(dropTargeted: dropTargeted)
            } else {
                EditorView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await studio.load(url: url) }
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .overlay(alignment: .top) {
            if studio.isRecording {
                RecordingBanner()
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: studio.isRecording)
        .sheet(isPresented: $studio.showRecorder) {
            RecorderSheet()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { studio.errorMessage != nil },
                set: { if !$0 { studio.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { studio.errorMessage = nil }
        } message: {
            Text(studio.errorMessage ?? "")
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @Environment(Studio.self) private var studio
    let dropTargeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
            Text("Drop a video to start")
                .font(.title2.weight(.semibold))
            Text("MOV, MP4, M4V, or anything QuickTime can play.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Open Video…") { studio.openVideoPanel() }
                    .keyboardShortcut("o")
                Button("Record Screen…") { studio.showRecorder = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(studio.isRecording)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .padding(28)
        )
    }
}

// MARK: - Editor

struct EditorView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio

        VStack(spacing: 16) {
            VideoPlayer(player: studio.player)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            TrimBar(
                start: $studio.start,
                end: $studio.end,
                duration: studio.duration,
                playhead: studio.currentTime
            ) { seconds in
                studio.scrub(to: seconds)
            }

            HStack(spacing: 12) {
                Label(
                    "\(TimeFormat.clock(studio.start)) → \(TimeFormat.clock(studio.end))",
                    systemImage: "scissors"
                )
                .monospacedDigit()
                Text("(\(String(format: "%.2f", studio.selectionLength)) s)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Set In") { studio.setInPoint() }
                    .keyboardShortcut("i", modifiers: [])
                Button("Set Out") { studio.setOutPoint() }
                    .keyboardShortcut("o", modifiers: [])
                Button {
                    studio.playSelection()
                } label: {
                    Label("Play Selection", systemImage: "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            .controlSize(.small)

            Divider()

            HStack(spacing: 20) {
                Picker("Width", selection: $studio.width) {
                    ForEach(studio.widthOptions, id: \.self) { value in
                        Text("\(value) px").tag(value)
                    }
                }
                .frame(width: 150)

                Picker("Frame rate", selection: $studio.fps) {
                    ForEach(Studio.fpsOptions, id: \.self) { value in
                        Text("\(value) fps").tag(value)
                    }
                }
                .frame(width: 160)

                Picker("Speed", selection: $studio.speed) {
                    ForEach(Studio.speedOptions, id: \.self) { value in
                        Text(speedLabel(value)).tag(value)
                    }
                }
                .frame(width: 130)

                Toggle("Boomerang", isOn: $studio.boomerang)
                    .toggleStyle(.checkbox)

                Spacer()
            }

            HStack(spacing: 12) {
                Text("\(studio.width) × \(studio.outputHeight) · \(studio.estimatedFrames) frames")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let name = studio.sourceURL?.lastPathComponent {
                    Text("·").foregroundStyle(.secondary)
                    Text(name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("New Video") { studio.clear() }
                    .disabled(studio.isExporting)
                Button("Record Screen…") { studio.showRecorder = true }
                    .disabled(studio.isExporting || studio.isRecording)
                Button {
                    studio.exportPanel()
                } label: {
                    Label("Export GIF…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("e")
                .disabled(studio.isExporting)
            }

            if studio.isExporting {
                ProgressView(value: studio.exportProgress) {
                    Text("Rendering frames…")
                }
                .progressViewStyle(.linear)
            }

            if let result = studio.lastExport {
                ExportCard(result: result)
            }
        }
        .padding(20)
    }

    private func speedLabel(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))×" : "\(value)×"
    }
}

// MARK: - Export result

struct ExportCard: View {
    let result: Studio.ExportResult

    var body: some View {
        HStack(spacing: 14) {
            if let image = NSImage(contentsOf: result.url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(result.url.lastPathComponent)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(TimeFormat.bytes(result.bytes)) · \(result.frames) frames · drag this card to share")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([result.url])
            }
            Button("Open") {
                NSWorkspace.shared.open(result.url)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.1))
        )
        .onDrag {
            NSItemProvider(contentsOf: result.url) ?? NSItemProvider()
        }
    }
}

// MARK: - Recording

struct RecordingBanner: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Text("Recording…")
                .fontWeight(.medium)
            Text("⌘⇧R to stop")
                .foregroundStyle(.secondary)
                .font(.callout)
            Button("Stop") {
                Task { await studio.stopRecording() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

struct RecorderSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true

    var body: some View {
        @Bindable var studio = studio

        VStack(alignment: .leading, spacing: 16) {
            Text("Record Screen")
                .font(.title2.weight(.bold))

            if loading {
                ProgressView("Looking for displays and windows…")
            } else if studio.captureTargets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing to capture yet.")
                    Text("If this is the first run, macOS needs you to allow Screen Recording for Loopsmith, then relaunch the app.")
                        .foregroundStyle(.secondary)
                    Button("Open Privacy Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                Picker("Capture", selection: $studio.selectedTargetID) {
                    Section("Displays") {
                        ForEach(studio.captureTargets.filter { $0.isDisplay }) { target in
                            Text(target.title).tag(Optional(target.id))
                        }
                    }
                    Section("Windows") {
                        ForEach(studio.captureTargets.filter { !$0.isDisplay }) { target in
                            Text(target.title).tag(Optional(target.id))
                        }
                    }
                }

                Picker("Capture rate", selection: $studio.recordingFPS) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Text("Loopsmith leaves itself out of display recordings and floats above other windows so the Stop button stays reachable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Refresh") {
                    Task {
                        loading = true
                        await studio.refreshTargets()
                        loading = false
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start Recording") {
                    Task { await studio.startRecording() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(studio.selectedTargetID == nil || loading)
            }
        }
        .padding(22)
        .frame(width: 480)
        .task {
            await studio.refreshTargets()
            loading = false
        }
    }
}
