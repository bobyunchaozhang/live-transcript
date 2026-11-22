enum TranscriptPresentation {
    struct Row: Identifiable {
        let line: TranscriptLine
        let startsSource: Bool
        var id: TranscriptLine.ID { line.id }
    }

    static func rows(for lines: [TranscriptLine]) -> [Row] {
        var previous: TranscriptSource?
        return lines.sorted { $0.arrival < $1.arrival }.map { line in
            let startsSource = previous != line.source
            previous = line.source
            return Row(line: line, startsSource: startsSource)
        }
    }
}
