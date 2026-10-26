import SwiftUI

/// Range selector with draggable in/out handles and a playhead marker.
struct TrimBar: View {
    @Binding var start: Double
    @Binding var end: Double
    let duration: Double
    let playhead: Double
    var onScrub: (Double) -> Void

    private enum Side { case start, end }

    private let handleWidth: CGFloat = 14
    private let height: CGFloat = 40
    private let minimumSpan: Double = 0.1

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let startX = x(for: start, in: width)
            let endX = x(for: end, in: width)
            let playheadX = x(for: playhead, in: width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.08))

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.28))
                    .frame(width: max(endX - startX, 0))
                    .offset(x: startX)

                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: playheadX - 1)

                handle(side: .start, x: startX - handleWidth / 2, width: width)
                handle(side: .end, x: endX - handleWidth / 2, width: width)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .coordinateSpace(.named("trim"))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
                    .onEnded { value in
                        onScrub(time(for: value.location.x, in: width))
                    }
            )
        }
        .frame(height: height)
        .padding(.horizontal, handleWidth / 2)
    }

    private func handle(side: Side, x: CGFloat, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor)
            .frame(width: handleWidth, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: 16)
            )
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .offset(x: x)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
                    .onChanged { value in
                        let seconds = time(for: value.location.x, in: width)
                        switch side {
                        case .start:
                            start = min(max(0, seconds), end - minimumSpan)
                            onScrub(start)
                        case .end:
                            end = max(min(duration, seconds), start + minimumSpan)
                            onScrub(end)
                        }
                    }
            )
    }

    private func x(for seconds: Double, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(seconds / duration) * width
    }

    private func time(for x: CGFloat, in width: CGFloat) -> Double {
        let clamped = min(max(x, 0), width)
        return Double(clamped / width) * duration
    }
}
