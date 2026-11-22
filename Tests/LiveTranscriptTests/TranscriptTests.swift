import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import LiveTranscript

@Test func revisionsReplaceDraftsAndAreOrderedAcrossSources() {
    var transcript = Transcript()
    transcript.apply(.init(source: .application, offset: 4, text: "远端草稿", isFinal: false))
    let draftID = transcript.lines[0].id
    transcript.apply(.init(source: .microphone, offset: 2, text: "本地发言", isFinal: true))
    transcript.apply(.init(source: .application, offset: 4, text: "远端定稿", isFinal: true))

    #expect(transcript.lines.map(\.text) == ["本地发言", "远端定稿"])
    #expect(transcript.lines.last?.id == draftID)
    #expect(transcript.lines.map(\.isFinal) == [true, true])
}

@Test func markdownReplacesRevisionsAndKeepsSourceLabels() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = try MarkdownOutput(startedAt: .now, directory: directory)
    var transcript = Transcript()
    transcript.apply(.init(source: .microphone, offset: 0, text: "这是草稿", isFinal: false))
    try await file.write(transcript.lines, revision: 1)
    let draft = try String(contentsOf: file.url, encoding: .utf8)
    #expect(draft.contains("**本机麦克风**（待定稿）"))

    transcript.apply(.init(source: .microphone, offset: 0, text: "确认 *中文* 正常。", isFinal: true))
    transcript.apply(.init(source: .application, offset: 1, text: "远端 ：收到 。", isFinal: true))
    try await file.write(transcript.lines, revision: 3)
    try await file.write([], revision: 2)
    let final = try String(contentsOf: file.url, encoding: .utf8)
    #expect(final.contains("**本机麦克风**"))
    #expect(final.contains("**应用音频**"))
    #expect(final.contains("远端：收到。"))
    #expect(final.contains("确认 \\*中文\\* 正常。"))
    #expect(!final.contains("草稿"))
    #expect(!final.contains("待定稿"))
}

@Test func audioResamplingPreservesGapsAndPreventsOverlaps() async throws {
    let sourceFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let speechFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let origin = CMTime(seconds: 100, preferredTimescale: 48_000)
    let (sequence, writer) = AsyncStream<SpeechAudioChunk>.makeStream()
    let input = SpeechAudioInput(source: .microphone, format: speechFormat, origin: origin, continuation: writer)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4_800))
    buffer.frameLength = 4_800
    let samples = try #require(buffer.floatChannelData?.pointee)
    samples.initialize(repeating: 0, count: 4_800)

    for offset in [0.01, 0.108, 0.5] {
        try input.append(buffer, at: origin + CMTime(seconds: offset, preferredTimescale: 48_000))
    }
    try input.finish()
    writer.finish()

    var times: [Double] = []
    for await packet in sequence {
        #expect(packet.source == .microphone)
        times.append(Double(packet.startSample) / 16_000)
    }
    #expect(times.count >= 3)
    #expect(abs(times[0] - 0.01) < 0.001)
    #expect((0.08...0.12).contains(times[1]))
    #expect(times.contains { abs($0 - 0.50) < 0.001 })
    #expect(times.sorted() == times)
}

@Test func showsSourceOncePerConsecutiveRun() {
    var transcript = Transcript()
    let sources: [TranscriptSource] = [.application, .application, .microphone, .microphone, .application]
    for (index, source) in sources.enumerated() {
        transcript.apply(.init(source: source, offset: Double(index), text: "第 \(index) 段", isFinal: true))
    }
    let rows = TranscriptPresentation.rows(for: transcript.lines)
    #expect(rows.map(\.startsSource) == [true, false, true, false, true])
    #expect(rows.map { $0.line.source } == sources)
}

@Test func trimsOnlyTimeAlignedPlaybackFromAnOverlappingMicrophoneLine() {
    var transcript = Transcript()
    transcript.apply(timedUpdate(.microphone, "我先补充。蓝色资料夹。预算加两千元。", at: 2))
    transcript.apply(timedUpdate(.application, "蓝色资料夹。", at: 2.5))
    #expect(transcript.lines.first { $0.source == .microphone }?.text == "我先补充。预算加两千元。")
    #expect(transcript.lines.first { $0.source == .application }?.text == "蓝色资料夹。")

    var repeatedLater = Transcript()
    repeatedLater.apply(timedUpdate(.application, "蓝色资料夹。", at: 2))
    repeatedLater.apply(timedUpdate(.microphone, "蓝色资料夹。", at: 4))
    #expect(repeatedLater.lines.count == 2)

    var shortReply = Transcript()
    shortReply.apply(timedUpdate(.application, "好的。", at: 2))
    shortReply.apply(timedUpdate(.microphone, "好的。", at: 2))
    #expect(shortReply.lines.count == 2)
}

private func timedUpdate(_ source: TranscriptSource, _ text: String, at start: TimeInterval) -> TranscriptUpdate {
    let timing: [TimedTranscriptCharacter] = text.enumerated().compactMap { index, character in
        guard character.isLetter || character.isNumber else { return nil }
        let time = start + Double(index) * 0.1
        return .init(value: character.lowercased(), index: index, start: time, end: time + 0.1)
    }
    return .init(source: source, offset: start, text: text, isFinal: false, timing: timing)
}

@Test func aLaterResultWithAnEarlierTimestampStillAppearsBelowTheExistingMessage() {
    var transcript = Transcript()
    transcript.apply(.init(source: .application, offset: 4, text: "English draft", isFinal: false))
    transcript.apply(.init(source: .microphone, offset: 3, text: "晚到的中文结果", isFinal: true))
    transcript.apply(.init(source: .application, offset: 4, text: "English final", isFinal: true))
    let rows = TranscriptPresentation.rows(for: transcript.lines)
    #expect(rows.map { $0.line.text } == ["English final", "晚到的中文结果"])
    #expect(transcript.lines.map(\.offset) == [3, 4])
}
