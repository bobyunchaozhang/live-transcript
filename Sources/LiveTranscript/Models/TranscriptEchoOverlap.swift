import Foundation

struct TimedTranscriptCharacter: Sendable {
    let value: String
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
}

enum TranscriptEchoOverlap {
    private static let timeTolerance = 0.48

    static func remove(
        _ microphone: TranscriptUpdate, matching playback: [TimedTranscriptCharacter]
    ) -> (text: String, offset: TimeInterval?) {
        guard let first = microphone.timing.first, let last = microphone.timing.last else {
            return (microphone.text, nil)
        }
        let render = playback.filter {
            $0.end >= first.start - timeTolerance && $0.start <= last.end + timeTolerance
        }
        guard render.count >= 4 else { return (microphone.text, nil) }

        let raw = Array(microphone.text)
        let local = microphone.timing
        let startsByValue = Dictionary(grouping: render.indices, by: { render[$0].value })
        var cuts: [Range<Int>] = []
        var index = 0

        while index < local.count {
            var longest = 0
            for start in startsByValue[local[index].value] ?? [] {
                var count = 0
                while index + count < local.count, start + count < render.count {
                    let a = local[index + count]
                    let b = render[start + count]
                    guard a.value == b.value, abs(a.start - b.start) <= timeTolerance,
                          a.end + timeTolerance >= b.start, b.end + timeTolerance >= a.start
                    else { break }
                    if count > 0 {
                        let previousEnd = local[index + count - 1].index + 1
                        if raw[previousEnd..<a.index].contains(where: { $0.isLetter || $0.isNumber }) {
                            break
                        }
                    }
                    count += 1
                }
                longest = max(longest, count)
            }

            if longest >= 4 {
                let start = local[index].index
                let end = local[index + longest - 1].index + 1
                if raw.indices.contains(start), end <= raw.count,
                   substantialPhrase(raw[start..<end])
                {
                    cuts.append(start..<end)
                    index += longest
                    continue
                }
            }
            index += 1
        }

        guard !cuts.isEmpty else { return (microphone.text, nil) }
        var remaining: [String] = []
        var begin = 0
        for cut in cuts {
            remaining.append(trimBoundary(raw[begin..<cut.lowerBound], leading: begin > 0, trailing: true))
            begin = cut.upperBound
        }
        remaining.append(trimBoundary(raw[begin...], leading: true, trailing: false))

        let offset = local.first {
            token in !cuts.contains { $0.contains(token.index) }
        }?.start
        let text = remaining.filter { !$0.isEmpty }.reduce(into: "") { result, part in
            if let last = result.last, let first = part.first, last.isASCII, first.isASCII,
               (last.isLetter || last.isNumber || last.isPunctuation),
               (first.isLetter || first.isNumber)
            {
                result += " "
            }
            result += part
        }
        return (text, offset)
    }

    private static func substantialPhrase(_ text: ArraySlice<Character>) -> Bool {
        let hanCount = text.filter { $0.unicodeScalars.contains { $0.properties.isIdeographic } }.count
        if hanCount >= 4 { return true }
        let words = text.split { !$0.isLetter && !$0.isNumber }
        return words.count >= 3 && words.reduce(0) { $0 + $1.count } >= 12
    }

    private static func trimBoundary(
        _ text: ArraySlice<Character>, leading: Bool, trailing: Bool
    ) -> String {
        var bounds = text
        if leading {
            while let first = bounds.first, first.isWhitespace || "，。！？；：、,.!?;:".contains(first) {
                bounds = bounds.dropFirst()
            }
        }
        if trailing {
            while let last = bounds.last, last.isWhitespace {
                bounds = bounds.dropLast()
            }
        }
        return String(bounds)
    }
}
