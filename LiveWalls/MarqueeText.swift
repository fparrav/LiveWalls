import SwiftUI

/// A single-line label that scrolls left, marquee-style, when it's wider
/// than the space it's given -- matching how a music player's now-playing
/// title scrolls instead of truncating with an ellipsis. Renders as a plain
/// static label when the text already fits.
///
/// Callers should attach `.id(text)` at the call site so a new video's
/// filename resets the measured width and restarts the scroll instead of
/// reusing the previous title's stale animation state.
struct MarqueeText: View {
    let text: String
    var font: Font = .caption2
    var foregroundColor: Color = .primary

    private let gap: CGFloat = 24
    private let pointsPerSecond: CGFloat = 22

    @State private var textWidth: CGFloat = 0
    @State private var scrolled = false

    var body: some View {
        GeometryReader { proxy in
            let overflows = textWidth > proxy.size.width && textWidth > 0

            Group {
                if overflows {
                    HStack(spacing: gap) {
                        label
                        label
                    }
                    .offset(x: scrolled ? -(textWidth + gap) : 0)
                    .onAppear {
                        withAnimation(
                            .linear(duration: Double((textWidth + gap) / pointsPerSecond))
                                .delay(1)
                                .repeatForever(autoreverses: false)
                        ) {
                            scrolled = true
                        }
                    }
                } else {
                    label
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: 14)
        .clipped()
        .background(
            label
                .fixedSize()
                .hidden()
                .background(
                    GeometryReader { textProxy in
                        Color.clear
                            .onAppear { textWidth = textProxy.size.width }
                    }
                )
        )
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .fixedSize()
    }
}
