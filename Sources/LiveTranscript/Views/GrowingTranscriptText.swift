import SwiftUI

struct GrowingTranscriptText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = ""
    @State private var stableCount = 0
    @State private var progress: Double

    let text: String
    let animateOnAppear: Bool

    init(text: String, animateOnAppear: Bool) {
        self.text = text
        self.animateOnAppear = animateOnAppear
        _progress = State(initialValue: animateOnAppear ? 0 : 1)
    }

    var body: some View {
        let current = shown.isEmpty ? text : shown
        let prefix = Text(verbatim: String(current.prefix(stableCount)))
        let suffix = Text(verbatim: String(current.dropFirst(stableCount))).customAttribute(NewTranscriptGlyph())

        Text("\(prefix)\(suffix)")
            .textRenderer(TranscriptGlyphFade(progress: reduceMotion ? 1 : progress))
            .task(id: text) {
                if reduceMotion || (shown.isEmpty && !animateOnAppear) {
                    shown = text
                    stableCount = text.count
                    progress = 1
                    return
                }

                let retained = zip(shown, text).prefix { $0 == $1 }.count
                guard retained < text.count else {
                    shown = text
                    stableCount = retained
                    return
                }

                withTransaction(Transaction(animation: nil)) {
                    shown = text
                    stableCount = retained
                    progress = 0
                }
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
                withAnimation(.easeOut(duration: 0.32)) {
                    progress = 1
                }
            }
    }
}

private struct NewTranscriptGlyph: TextAttribute {}

private struct TranscriptGlyphFade: TextRenderer {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var glyphIndex = 0

        for line in layout {
            for run in line {
                if run[NewTranscriptGlyph.self] == nil || progress >= 1 {
                    context.draw(run)
                    continue
                }

                for slice in run {
                    let delay = min(0.42, Double(glyphIndex) * 0.025)
                    let opacity = min(1, max(0, (progress - delay) / (0.68 - delay)))
                    var drawing = context
                    drawing.opacity *= opacity
                    drawing.draw(slice)
                    glyphIndex += 1
                }
            }
        }
    }
}
