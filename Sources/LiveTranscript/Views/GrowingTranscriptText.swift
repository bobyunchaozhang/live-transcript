import SwiftUI

struct GrowingTranscriptText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transition: TranscriptTextTransition

    let text: String

    init(text: String, animateOnAppear: Bool) {
        self.text = text
        _transition = State(initialValue: TranscriptTextTransition(
            text: text, revealAt: animateOnAppear ? Self.now : nil
        ))
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var body: some View {
        let endsAt = transition.endsAt
        Group {
            if reduceMotion {
                Text(verbatim: text)
            } else if endsAt != nil {
                animatedText
            } else {
                Text(verbatim: transition.current.text)
            }
        }
        .onChange(of: text) {
            if reduceMotion {
                transition = TranscriptTextTransition(text: text)
            } else {
                transition.update(to: text, at: Self.now)
            }
        }
        .onChange(of: reduceMotion) {
            if reduceMotion { transition = TranscriptTextTransition(text: text) }
        }
        .task(id: endsAt) {
            guard let endsAt else { return }
            do { try await Task.sleep(for: .seconds(max(0, endsAt - Self.now))) }
            catch { return }
            if !Task.isCancelled { transition = TranscriptTextTransition(text: transition.current.text) }
        }
    }

    private var animatedText: some View {
        let current = styledText(transition.current)
        let outgoing = transition.departures.map {
            (departure: $0, text: styledText($0.snapshot, hidingPrefix: $0.prefixLength))
        }

        return TimelineView(.animation) { _ in
            let time = Self.now
            current
                .textRenderer(TranscriptGlyphFade(time: time))
                .background(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(outgoing, id: \.departure.id) { layer in
                            layer.text
                                .textRenderer(TranscriptGlyphFade(time: layer.departure.startedAt))
                                .opacity(layer.departure.opacity(at: time))
                                .textSelection(.disabled)
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                    }
                }
        }
    }

    private func styledText(_ snapshot: TranscriptTextTransition.Snapshot, hidingPrefix prefix: Int = 0) -> Text {
        let characters = Array(snapshot.text)
        var text = Text(verbatim: String(characters.prefix(prefix))).customAttribute(HiddenTranscriptGlyph())
        var cursor = prefix

        for (index, reveal) in snapshot.reveals.enumerated() where reveal.range.upperBound > prefix {
            let start = max(prefix, reveal.range.lowerBound)
            let settled = Text(verbatim: String(characters[cursor..<start]))
            let fading = Text(verbatim: String(characters[start..<reveal.range.upperBound]))
                .customAttribute(RevealingTranscriptGlyph(index: index, skipped: start - reveal.range.lowerBound, reveal: reveal))
            text = Text("\(text)\(settled)\(fading)")
            cursor = reveal.range.upperBound
        }
        let tail = Text(verbatim: String(characters[cursor...]))
        return Text("\(text)\(tail)")
    }
}

private struct HiddenTranscriptGlyph: TextAttribute {}

private struct RevealingTranscriptGlyph: TextAttribute {
    let index: Int
    let skipped: Int
    let reveal: TranscriptTextTransition.Reveal
}

private struct TranscriptGlyphFade: TextRenderer {
    let time: TimeInterval

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var glyphCounts: [Int: Int] = [:]

        for line in layout {
            for run in line where run[HiddenTranscriptGlyph.self] == nil {
                guard let attribute = run[RevealingTranscriptGlyph.self], time < attribute.reveal.endsAt else {
                    context.draw(run)
                    continue
                }
                for slice in run {
                    let glyph = glyphCounts[attribute.index, default: attribute.skipped]
                    glyphCounts[attribute.index] = glyph + 1
                    var drawing = context
                    drawing.opacity *= attribute.reveal.opacity(at: time, glyph: glyph)
                    drawing.draw(slice)
                }
            }
        }
    }
}
