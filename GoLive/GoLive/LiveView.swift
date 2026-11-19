import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var controller: LiveController
    @EnvironmentObject private var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Always in the hierarchy so the mixer keeps one preview output for the app's lifetime.
            CameraPreview(mixer: controller.broadcaster.mixer)
                .ignoresSafeArea()
                .opacity(controller.showsCamera ? 1 : 0)
            if controller.showsCamera {
                // Keeps the controls legible over bright scenes.
                VStack {
                    LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 180)
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 240)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            switch controller.phase {
            case .idle:
                IdleScreen(showSettings: $showSettings)
            case .starting(let message):
                Rotated(degrees: controller.uiRotation) { OnAirOverlay(connecting: message) }
            case .live:
                Rotated(degrees: controller.uiRotation) { OnAirOverlay(connecting: nil) }
            case .ending:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text("Ending stream").font(.system(.headline, design: .rounded))
                }
            case .ended(let summary):
                ResultScreen(symbol: "checkmark.circle.fill", tint: .white, headline: "Stream ended", detail: summary, showSettings: $showSettings)
            case .failed(let message):
                ResultScreen(symbol: "exclamationmark.triangle.fill", tint: Theme.amber, headline: "Didn't go live", detail: message, showSettings: $showSettings)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.phase)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

/// Turns its content to match a sideways phone, since the app's own interface stays portrait.
private struct Rotated<Content: View>: View {
    let degrees: Double
    @ViewBuilder var content: Content

    var body: some View {
        if degrees == 0 {
            content
        } else {
            GeometryReader { geo in
                content
                    .padding(.horizontal, 44)
                    .padding(.vertical, 18)
                    .frame(width: geo.size.height, height: geo.size.width)
                    .rotationEffect(.degrees(degrees))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - On air

private struct OnAirOverlay: View {
    @EnvironmentObject private var controller: LiveController
    /// Status text while YouTube is still spinning up; nil once the broadcast is live.
    let connecting: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Badge(live: connecting == nil)
                        if let started = controller.startedAt, connecting == nil {
                            TimelineView(.periodic(from: started, by: 1)) { context in
                                Text(LiveController.clock(context.date.timeIntervalSince(started)))
                                    .font(.system(.headline, design: .rounded).monospacedDigit())
                            }
                        }
                    }
                    Text(controller.title)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    if let connecting {
                        Text(connecting)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    } else if controller.isReconnecting {
                        Label("Reconnecting", systemImage: "wifi.exclamationmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.amber)
                    }
                }
                Spacer()
                VStack(spacing: 12) {
                    if let url = controller.watchURL {
                        ShareLink(item: url) { RoundIcon(symbol: "square.and.arrow.up") }
                    }
                    if !controller.isFront {
                        Button(action: controller.toggleTorch) {
                            RoundIcon(symbol: controller.isTorchOn ? "bolt.fill" : "bolt.slash.fill", active: controller.isTorchOn)
                        }
                    }
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 6)

            Spacer()

            HStack {
                Button(action: controller.toggleMute) {
                    RoundIcon(symbol: controller.isMuted ? "mic.slash.fill" : "mic.fill", size: 56, active: controller.isMuted)
                }
                Spacer()
                Button(action: controller.stop) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 84, height: 84)
                        RoundedRectangle(cornerRadius: 8).fill(Theme.red).frame(width: 34, height: 34)
                    }
                }
                .accessibilityLabel(connecting == nil ? "End stream" : "Cancel")
                Spacer()
                Button(action: controller.flipCamera) {
                    RoundIcon(symbol: "arrow.triangle.2.circlepath.camera.fill", size: 56)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .foregroundStyle(.white)
    }
}

private struct Badge: View {
    let live: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.35 : 1)
            Text(live ? "LIVE" : "CONNECTING")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .kerning(1.2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(live ? Theme.red : Color.white.opacity(0.22), in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct RoundIcon: View {
    let symbol: String
    var size: CGFloat = 46
    var active = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(active ? .black : .white)
            .frame(width: size, height: size)
            .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
    }
}

// MARK: - Off air

private struct IdleScreen: View {
    @EnvironmentObject private var controller: LiveController
    @EnvironmentObject private var settings: AppSettings
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GoLive").font(.system(.title2, design: .rounded).weight(.heavy))
                    if !settings.channelTitle.isEmpty {
                        Text(settings.channelTitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { showSettings = true } label: { RoundIcon(symbol: "gearshape.fill") }
            }
            Spacer()
            GoButton(label: "GO LIVE", action: controller.start)
            Text("Next up: Live stream \(settings.nextNumber)")
                .font(.system(.headline, design: .rounded))
                .padding(.top, 28)
            Text("\(settings.privacy.label) · \(settings.quality.label)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer()
            Spacer()
        }
        .padding(24)
    }
}

private struct ResultScreen: View {
    @EnvironmentObject private var controller: LiveController
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { showSettings = true } label: { RoundIcon(symbol: "gearshape.fill") }
            }
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(tint)
            Text(headline)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .padding(.top, 16)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let url = controller.watchURL {
                ShareLink(item: url) {
                    Label("Share the video", systemImage: "square.and.arrow.up")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .tint(.white)
                .padding(.top, 18)
            }
            Spacer()
            GoButton(label: "GO AGAIN", diameter: 132, action: controller.start)
            Spacer()
        }
        .padding(24)
    }
}

private struct GoButton: View {
    let label: String
    var diameter: CGFloat = 196
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.red.opacity(0.18)).frame(width: diameter * 1.22, height: diameter * 1.22)
                Circle().fill(Theme.red).frame(width: diameter, height: diameter)
                    .shadow(color: Theme.red.opacity(0.6), radius: 30)
                Text(label)
                    .font(.system(size: diameter * 0.15, weight: .heavy, design: .rounded))
                    .kerning(1.5)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}
