import Foundation

actor MarkdownOutput {
    nonisolated let url: URL
    private let heading: String
    private var lastWrittenRevision = -1

    init(startedAt: Date, directory: URL? = nil) throws {
        let destination = if let directory {
            directory
        } else {
            try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "会听/转写", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let fileDate = DateFormatter()
        fileDate.locale = Locale(identifier: "en_US_POSIX")
        fileDate.timeZone = BeijingTime.zone
        fileDate.dateFormat = "yyyy-MM-dd HHmmss"
        let suffix = UUID().uuidString.prefix(6)
        url = destination.appending(path: "\(fileDate.string(from: startedAt))-\(suffix).md")

        let displayedDate = BeijingTime.dateAndTime(startedAt)
        heading = "# 会听转写\n\n- 开始时间：\(displayedDate)\n- 时间戳：北京时间（UTC+08:00）\n- 识别语言：中文、英文\n\n## 对话\n"
        try (heading + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func write(_ lines: [TranscriptLine], revision: Int) throws {
        guard revision > lastWrittenRevision else { return }

        var markdown = heading
        for line in lines {
            let status = line.isFinal ? "" : "（待定稿）"
            markdown += "\n- `\(line.timestamp)` **\(line.source.title)**\(status)  \n  \(Self.escape(line.text))\n"
        }
        // A reader opening the file during a write sees one complete snapshot.
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        lastWrittenRevision = revision
    }

    private static func escape(_ text: String) -> String {
        let specials = "\\`*_{}[]<>()#+-.!|~&>"
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flattened.reduce(into: "") { escaped, character in
            if specials.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
    }
}
