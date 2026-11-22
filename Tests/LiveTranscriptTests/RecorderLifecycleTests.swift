import Foundation
import Testing
@testable import LiveTranscript

@Test @MainActor func requestingStopDoesNotEndTheSessionUntilConfirmed() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = try MarkdownOutput(startedAt: .now, directory: folder)
    let session = TestRecordingSession(markdown: output)
    let model = RecorderModel(prepareSession: { _ in session })

    model.toggle()
    await model.waitForTransition()
    model.toggle()
    #expect(model.showsStopConfirmation)
    #expect(model.phase == .recording)
    #expect(session.capturing)

    model.showsStopConfirmation = false
    await session.send("取消后继续写入", offset: 4, to: 0)
    model.pauseOrResume()
    await model.waitForTransition()
    model.toggle()
    #expect(model.showsStopConfirmation)
    #expect(model.phase == .paused)

    await model.stopAndWait()
    #expect(!model.showsStopConfirmation)
    #expect(model.phase == .idle)
    #expect(session.releases == 1)
    #expect(try String(contentsOf: output.url, encoding: .utf8).contains("取消后继续写入"))
}

@Test @MainActor func pauseReleasesInputsAndResumeContinuesTheSameMarkdown() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = try MarkdownOutput(startedAt: .now, directory: folder)
    let session = TestRecordingSession(markdown: output)
    let model = RecorderModel(prepareSession: { _ in session })

    model.toggle()
    await model.waitForTransition()
    #expect(model.phase == .recording)
    #expect(model.fileURL == output.url)

    await session.send("暂停前第一段", offset: 4, to: 0)
    model.pauseOrResume()
    await model.waitForTransition()
    #expect(model.phase == .paused)
    #expect(!session.capturing)
    #expect(session.releases == 1)
    let paused = try String(contentsOf: output.url, encoding: .utf8)
    #expect(paused.contains("暂停前第一段"))
    #expect(!paused.contains("待定稿"))

    await session.send("暂停期间的旧回调", offset: 7, to: 0)
    #expect(model.lines.map(\.text) == ["暂停前第一段"])

    session.failNextStart = true
    model.pauseOrResume()
    await model.waitForTransition()
    #expect(model.phase == .paused)
    #expect(model.issue != nil)
    #expect(model.fileURL == output.url)

    model.pauseOrResume()
    await model.waitForTransition()
    #expect(model.phase == .recording)
    #expect(model.issue == nil)
    #expect(model.fileURL == output.url)
    await session.send("继续后第二段", offset: 64, to: 1)
    await session.send("上次采集的延迟回调", offset: 65, to: 0)

    await model.stopAndWait()
    #expect(model.phase == .idle)
    #expect(!session.capturing)
    #expect(session.releases == 2)
    let final = try String(contentsOf: output.url, encoding: .utf8)
    #expect(final.contains("暂停前第一段"))
    #expect(final.contains("继续后第二段"))
    #expect(!final.contains("延迟回调"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [output.url.lastPathComponent])
}

@Test @MainActor func stoppingDuringPauseDrainsThePendingCaptureOnlyOnce() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = try MarkdownOutput(startedAt: .now, directory: folder)
    let session = TestRecordingSession(markdown: output)
    let model = RecorderModel(prepareSession: { _ in session })

    model.toggle()
    await model.waitForTransition()
    await session.send("尚未写入", offset: 0, to: 0)
    model.pauseOrResume()
    #expect(model.phase == .pausing)
    await model.stopAndWait()
    #expect(model.phase == .idle)
    #expect(session.releases == 1)
    #expect(try String(contentsOf: output.url, encoding: .utf8).contains("尚未写入"))
}

@Test func beijingTimestampsFollowTheSpokenTimeAcrossMidnight() async throws {
    let iso = ISO8601DateFormatter()
    let before = try #require(iso.date(from: "2026-11-21T15:59:58Z"))
    let after = try #require(iso.date(from: "2026-11-21T16:00:08Z"))
    var transcript = Transcript()
    transcript.apply(.init(source: .application, offset: 0, text: "暂停前", isFinal: true, recordedAt: before))
    transcript.apply(.init(source: .microphone, offset: 10, text: "恢复后", isFinal: true, recordedAt: after))
    #expect(transcript.lines.map(\.timestamp) == ["23:59:58", "00:00:08"])

    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = try MarkdownOutput(startedAt: before, directory: folder)
    try await output.write(transcript.lines, revision: 0)
    let written = try String(contentsOf: output.url, encoding: .utf8)
    #expect(output.url.lastPathComponent.hasPrefix("2026-11-21 235958"))
    #expect(written.contains("2026-11-21 23:59:58+08:00"))
    #expect(written.contains("北京时间（UTC+08:00）"))
    #expect(written.contains("`23:59:58`"))
    #expect(written.contains("`00:00:08`"))
}

@MainActor
private final class TestRecordingSession: RecordingSession {
    let markdown: MarkdownOutput
    var failNextStart = false
    private(set) var capturing = false
    private(set) var releases = 0
    private var callbacks: [@Sendable (TranscriptUpdate) async -> Void] = []

    init(markdown: MarkdownOutput) { self.markdown = markdown }

    func startAudio(
        onUpdate: @escaping @Sendable (TranscriptUpdate) async -> Void,
        onError: @escaping @Sendable (any Error) -> Void
    ) async throws {
        if failNextStart {
            failNextStart = false
            throw CaptureError.microphoneUnavailable
        }
        capturing = true
        callbacks.append(onUpdate)
    }

    func stopAudio() async throws {
        if capturing {
            capturing = false
            releases += 1
        }
    }

    func send(_ text: String, offset: Double, to run: Int) async {
        await callbacks[run](.init(source: .application, offset: offset, text: text, isFinal: true))
    }
}
