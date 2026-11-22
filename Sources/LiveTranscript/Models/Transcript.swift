import Foundation

enum TranscriptSource: String, Hashable, Sendable {
    case microphone
    case application

    var title: String {
        switch self {
        case .microphone: "本机麦克风"
        case .application: "应用音频"
        }
    }

}

struct TranscriptUpdate: Sendable {
    let source: TranscriptSource
    let offset: TimeInterval
    let text: String
    let isFinal: Bool
    var timing: [TimedTranscriptCharacter] = []
    var recordedAt: Date?
}

struct TranscriptLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let arrival: Int
    let source: TranscriptSource
    let offset: TimeInterval
    let recordedAt: Date
    let text: String
    let isFinal: Bool

    var timestamp: String { BeijingTime.clock(recordedAt) }
}

struct Transcript {
    private let startedAt = Date()
    private var finalLines: [TranscriptLine] = []
    private var nextArrival = 0
    private var drafts: [TranscriptSource: TranscriptLine] = [:]
    private var microphoneDraft: TranscriptUpdate?
    private var applicationTiming: [TimedTranscriptCharacter] = []
    private var applicationDraftTiming: [TimedTranscriptCharacter] = []

    var lines: [TranscriptLine] {
        var ordered = finalLines
        if let draft = drafts[.application] {
            Self.insert(draft, into: &ordered)
        }
        if let draft = drafts[.microphone] {
            let cleaned = microphoneDraft.map { cleanedLine(draft, from: $0) } ?? draft
            if !cleaned.text.isEmpty {
                Self.insert(cleaned, into: &ordered)
            }
        }
        return ordered
    }

    mutating func apply(_ update: TranscriptUpdate) {
        if update.source == .application {
            applicationDraftTiming = update.isFinal ? [] : update.timing
            if update.isFinal {
                applicationTiming.append(contentsOf: update.timing)
                // Only contemporaneous speech can match a live draft or a new final result.
                if let latest = applicationTiming.last?.start {
                    applicationTiming.removeAll { latest - $0.start > 120 }
                }
            }
        } else {
            microphoneDraft = update.isFinal ? nil : update
        }

        let text = Self.format(update.text)
        let draft = drafts.removeValue(forKey: update.source)
        guard !text.isEmpty else { return }

        let offset = update.offset.isFinite ? max(0, update.offset) : 0
        let line = TranscriptLine(
            id: draft?.id ?? UUID(),
            arrival: draft?.arrival ?? nextArrival,
            source: update.source,
            offset: offset,
            recordedAt: update.recordedAt ?? startedAt.addingTimeInterval(offset),
            text: text,
            isFinal: update.isFinal
        )
        if draft == nil { nextArrival += 1 }

        if update.isFinal {
            let cleaned = update.source == .microphone ? cleanedLine(line, from: update) : line
            if !cleaned.text.isEmpty {
                Self.insert(cleaned, into: &finalLines)
            }
        } else {
            drafts[update.source] = line
        }
    }

    private func cleanedLine(_ line: TranscriptLine, from update: TranscriptUpdate) -> TranscriptLine {
        guard !update.timing.isEmpty else { return line }
        let cleaned = TranscriptEchoOverlap.remove(
            update, matching: applicationTiming + applicationDraftTiming
        )
        let offset = cleaned.offset ?? line.offset
        return TranscriptLine(
            id: line.id, arrival: line.arrival, source: line.source, offset: offset,
            recordedAt: line.recordedAt.addingTimeInterval(offset - line.offset),
            text: Self.format(cleaned.text), isFinal: line.isFinal
        )
    }

    private static func format(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[\t ]+([，。！？；：、）】》」])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([（【《「])[\t ]+"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func insert(_ line: TranscriptLine, into lines: inout [TranscriptLine]) {
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let next = (lower + upper) / 2
            let existing = lines[next]
            let belongsBefore = (line.offset, line.source.rawValue) < (existing.offset, existing.source.rawValue)
            if belongsBefore {
                upper = next
            } else {
                lower = next + 1
            }
        }
        lines.insert(line, at: lower)
    }
}
