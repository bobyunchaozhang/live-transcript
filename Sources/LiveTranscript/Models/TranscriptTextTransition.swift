import Foundation

struct TranscriptTextTransition {
    struct Reveal: Hashable {
        static let duration = 0.24
        static let maximumDelay = 0.12

        let range: Range<Int>
        let startedAt: TimeInterval

        var endsAt: TimeInterval { startedAt + Self.maximumDelay + Self.duration }

        func opacity(at time: TimeInterval, glyph: Int) -> Double {
            let delay = min(Self.maximumDelay, Double(glyph) * 0.012)
            return TranscriptTextTransition.ease((time - startedAt - delay) / Self.duration)
        }
    }

    struct Snapshot {
        var text: String
        var reveals: [Reveal] = []
    }

    struct Departure: Identifiable {
        let id = UUID()
        let snapshot: Snapshot
        let prefixLength: Int
        let startedAt: TimeInterval

        var endsAt: TimeInterval { startedAt + 0.18 }

        func opacity(at time: TimeInterval) -> Double {
            1 - TranscriptTextTransition.ease((time - startedAt) / (endsAt - startedAt))
        }
    }

    private(set) var current: Snapshot
    private(set) var departures: [Departure] = []

    init(text: String, revealAt time: TimeInterval? = nil) {
        current = Snapshot(text: text)
        if let time, !text.isEmpty {
            current.reveals = [Reveal(range: 0..<text.count, startedAt: time)]
        }
    }

    var endsAt: TimeInterval? {
        [current.reveals.last?.endsAt, departures.last?.endsAt].compactMap { $0 }.max()
    }

    mutating func update(to text: String, at time: TimeInterval) {
        guard current.text != text else { return }
        departures.removeAll { $0.endsAt <= time }
        current.reveals.removeAll { $0.endsAt <= time }

        let shared = zip(current.text, text).prefix { $0 == $1 }.count
        if shared < current.text.count {
            departures.append(Departure(snapshot: current, prefixLength: shared, startedAt: time))
        }
        // Preserve the clocks for glyphs that were already appearing before this update.
        current.reveals = current.reveals.prefix { $0.range.lowerBound < shared }.map { reveal in
            Reveal(range: reveal.range.clamped(to: 0..<shared), startedAt: reveal.startedAt)
        }
        if shared < text.count {
            current.reveals.append(Reveal(range: shared..<text.count, startedAt: time))
        }
        current.text = text
    }

    private static func ease(_ fraction: Double) -> Double {
        let progress = min(1, max(0, fraction))
        return progress * progress * (3 - 2 * progress)
    }
}
