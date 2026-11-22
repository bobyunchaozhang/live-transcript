import Foundation

struct BilingualSnapshot: Decodable {
    let text: String
    let tokens: [String]
    let timestamps: [Double]
    let startTime: Double

    private enum CodingKeys: String, CodingKey {
        case text, tokens, timestamps
        case startTime = "start_time"
    }

    func characterTiming(startedAt: Double) -> [TimedTranscriptCharacter] {
        guard tokens.count == timestamps.count else { return [] }
        let positions = text.enumerated().compactMap { index, character -> (Int, String)? in
            guard character.isLetter || character.isNumber else { return nil }
            return (index, character.lowercased())
        }
        var timing: [TimedTranscriptCharacter] = []
        var next = 0

        for (tokenIndex, token) in tokens.enumerated() {
            let letters = token.filter { $0.isLetter || $0.isNumber }.map { $0.lowercased() }
            guard !letters.isEmpty, next < positions.count, timestamps[tokenIndex].isFinite else { continue }
            let end = min(positions.count, next + 5)
            guard let match = (next..<end).first(where: {
                let end = $0 + letters.count
                return end <= positions.count && positions[$0..<end].map(\.1) == letters
            }) else { continue }

            let start = timestamps[tokenIndex]
            let following = tokenIndex + 1
            let finish = following < timestamps.count ? timestamps[following] : start + 0.12
            let step = max(0.025, min(0.35, finish - start)) / Double(letters.count)
            for offset in letters.indices {
                timing.append(TimedTranscriptCharacter(
                    value: letters[offset], index: positions[match + offset].0,
                    start: startedAt + start + Double(offset) * step,
                    end: startedAt + start + Double(offset + 1) * step
                ))
            }
            next = match + letters.count
        }
        return timing
    }
}
