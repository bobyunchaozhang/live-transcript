import AppKit
import SwiftUI

struct EmptyConversationArtwork: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isListening: Bool

    private static let iconImage: NSImage? = Bundle.main
        .url(forResource: "VoiceInput", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        let dark = colorScheme == .dark
        let green = Color(red: 0.65, green: 0.91, blue: 0.80)
        let blue = dark ? Color(red: 0.62, green: 0.75, blue: 0.98)
            : Color(red: 0.29, green: 0.51, blue: 0.79)

        ZStack {
            Circle()
                .fill(green.opacity(dark ? 0.12 : 0.28))
                .frame(width: 134, height: 134)

            HStack(spacing: 6) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(blue)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 74, height: 44)
            .background(
                dark ? Color(red: 0.19, green: 0.30, blue: 0.47)
                    : Color(red: 0.83, green: 0.90, blue: 1),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 15, bottomLeadingRadius: 15,
                    bottomTrailingRadius: 4, topTrailingRadius: 15
                )
            )
            .offset(x: 28, y: -22)

            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isListening || reduceMotion)) { context in
                let pulse = isListening && !reduceMotion
                    ? 1 + 0.05 * sin(context.date.timeIntervalSinceReferenceDate * 3)
                    : 1

                voiceInput
                    .frame(width: 36, height: 36)
                    .scaleEffect(pulse)
            }
            .frame(width: 90, height: 57)
            .background(
                green,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 5,
                    bottomTrailingRadius: 16, topTrailingRadius: 16
                )
            )
            .shadow(color: .black.opacity(dark ? 0.20 : 0.09), radius: 5, y: 3)
            .offset(x: -16, y: 10)
        }
        .frame(width: 170, height: 148)
        .offset(y: -12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var voiceInput: some View {
        if let image = Self.iconImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "mic")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.black)
        }
    }
}
