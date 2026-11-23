import Foundation
import Observation

@MainActor
@Observable
final class RecorderModel {
    enum Phase {
        case idle, preparing, recording, pausing, paused, resuming, stopping

        var title: String {
            switch self {
            case .idle: "已停止"
            case .preparing: "正在准备"
            case .recording: "转写中"
            case .pausing: "正在暂停"
            case .paused: "已暂停"
            case .resuming: "正在继续"
            case .stopping: "正在停止"
            }
        }

        var buttonTitle: String {
            switch self {
            case .idle: "开始转写"
            case .preparing: "取消准备"
            case .recording, .pausing, .paused, .resuming, .stopping: "停止转写"
            }
        }

        var buttonSymbol: String {
            switch self {
            case .idle: "record.circle"
            case .preparing: "xmark"
            case .recording, .pausing, .paused, .resuming, .stopping: "stop.fill"
            }
        }

        var showsPauseButton: Bool {
            self == .recording || self == .pausing || self == .paused || self == .resuming
        }

        var canPauseOrResume: Bool { self == .recording || self == .paused }
        var offersResume: Bool { self == .paused || self == .resuming }
        var isBusy: Bool { self == .preparing || self == .pausing || self == .resuming || self == .stopping }
    }

    typealias PrepareSession = @MainActor (@escaping @MainActor (String) -> Void) async throws -> any RecordingSession

    private(set) var phase: Phase = .idle
    private(set) var detail = ""
    private(set) var fileURL: URL?
    private(set) var issue: String?
    private(set) var microphoneIssue: String?
    private(set) var diskIssue: String?
    private(set) var permissionSettings: URL?
    var showsStopConfirmation = false

    let microphoneInputs: MicrophoneInputs
    private let prepareSession: PrepareSession
    private var transcript = Transcript()
    @ObservationIgnored private var incoming: Transcript?
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private var session: (any RecordingSession)?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var scheduledWrite: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var microphoneRevision = 0

    init(
        prepareSession: @escaping PrepareSession = LiveSession.prepare(onStatus:),
        microphoneInputs: MicrophoneInputs = MicrophoneInputs()
    ) {
        self.prepareSession = prepareSession
        self.microphoneInputs = microphoneInputs
    }

    var lines: [TranscriptLine] { transcript.lines }

    func observeMicrophones() {
        microphoneInputs.observeChanges { [weak self] in self?.applyMicrophonePreference() }
    }

    func chooseMicrophone(_ id: String?) {
        microphoneInputs.select(id)
        microphoneIssue = nil
        applyMicrophonePreference()
    }

    private func applyMicrophonePreference() {
        guard phase == .recording, let session, let runID else { return }
        microphoneRevision += 1
        let revision = microphoneRevision
        session.selectMicrophone(microphoneInputs.preferredID) { [weak self] result in
            Task { @MainActor in
                guard let self, self.phase == .recording, self.runID == runID,
                      self.microphoneRevision == revision else { return }
                switch result {
                case .success: self.microphoneIssue = nil
                case .failure: self.microphoneIssue = "无法切换麦克风，请从顶部菜单选择可用的输入。"
                }
            }
        }
    }

    func toggle() {
        switch phase {
        case .idle:
            start()
        case .preparing:
            stop()
        case .recording, .pausing, .paused, .resuming:
            showsStopConfirmation = true
        case .stopping:
            break
        }
    }

    func pauseOrResume() {
        guard let session else { return }
        switch phase {
        case .recording:
            endAudio(session, next: .pausing)
        case .paused:
            resume(session)
        default:
            break
        }
    }

    func stop() {
        showsStopConfirmation = false
        switch phase {
        case .preparing, .resuming:
            phase = .stopping
            transition?.cancel()
        case .recording, .paused:
            if let session { endAudio(session, next: .stopping) }
        case .pausing:
            phase = .stopping
        case .idle, .stopping:
            break
        }
    }

    func stopAndWait() async {
        stop()
        await waitForTransition()
    }

    func waitForTransition() async {
        await transition?.value
    }

    private func start() {
        dismissIssue()
        incoming = Transcript()
        phase = .preparing
        detail = "正在检查麦克风权限…"

        transition = Task { [self] in
            var opened: (any RecordingSession)?
            do {
                let live = try await prepareSession { [weak self] status in
                    guard self?.phase == .preparing else { return }
                    self?.detail = status
                }
                opened = live
                try Task.checkCancellation()
                detail = "正在连接麦克风和应用音频…"
                try await startAudio(live)

                session = live
                transcript = incoming ?? Transcript()
                incoming = nil
                revision = 0
                diskIssue = nil
                fileURL = live.markdown.url
                await completeStart(live)
            } catch {
                if let opened { try? FileManager.default.removeItem(at: opened.markdown.url) }
                record(error)
                incoming = nil
                runID = nil
                transition = nil
                phase = .idle
            }
        }
    }

    private func resume(_ live: any RecordingSession) {
        dismissIssue()
        phase = .resuming
        transition = Task {
            do {
                try await startAudio(live)
                await completeStart(live)
            } catch {
                record(error)
                runID = nil
                if phase == .stopping {
                    await completeEnd(live)
                } else {
                    transition = nil
                    phase = .paused
                }
            }
        }
    }

    private func startAudio(_ live: any RecordingSession) async throws {
        let id = UUID()
        runID = id
        try await live.startAudio(
            microphoneID: microphoneInputs.preferredID,
            onUpdate: { [weak self] update in
                await self?.receive(update, for: id)
            },
            onError: { [weak self] error in
                Task { @MainActor in self?.interrupt(error, for: id) }
            }
        )
    }

    private func completeStart(_ live: any RecordingSession) async {
        if phase == .stopping {
            await completeEnd(live)
        } else {
            transition = nil
            phase = .recording
            applyMicrophonePreference()
            if !lines.isEmpty { scheduleWrite() }
        }
    }

    private func endAudio(_ live: any RecordingSession, next: Phase) {
        phase = next
        transition = Task {
            await completeEnd(live)
        }
    }

    private func completeEnd(_ live: any RecordingSession) async {
        do {
            try await live.stopAudio()
        } catch {
            record(error)
            phase = .stopping
        }

        runID = nil
        scheduledWrite?.cancel()
        scheduledWrite = nil
        await writeSnapshot(to: live.markdown)

        transition = nil
        if phase == .stopping {
            showsStopConfirmation = false
            session = nil
            phase = .idle
        } else {
            phase = .paused
        }
    }

    private func receive(_ update: TranscriptUpdate, for id: UUID) {
        guard id == runID else { return }
        if incoming != nil {
            incoming?.apply(update)
        } else {
            transcript.apply(update)
            if phase == .recording { scheduleWrite() }
        }
    }

    private func scheduleWrite() {
        guard scheduledWrite == nil, let output = session?.markdown else { return }
        scheduledWrite = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(450))
            } catch { return }
            guard let self else { return }
            scheduledWrite = nil
            await writeSnapshot(to: output)
        }
    }

    private func writeSnapshot(to output: MarkdownOutput) async {
        revision += 1
        let snapshotRevision = revision
        do {
            try await output.write(lines, revision: snapshotRevision)
            if revision == snapshotRevision, fileURL == output.url { diskIssue = nil }
        } catch {
            if revision == snapshotRevision, fileURL == output.url {
                diskIssue = "无法更新 Markdown。窗口中的文字仍可复制。\(error.localizedDescription)"
            }
        }
    }

    private func interrupt(_ error: any Error, for id: UUID) {
        guard id == runID, issue == nil else { return }
        record(error)
        if phase == .resuming {
            transition?.cancel()
        } else {
            stop()
        }
    }

    private func record(_ error: any Error) {
        guard !(error is CancellationError), issue == nil else { return }
        issue = error.localizedDescription
        switch error as? CaptureError {
        case .microphonePermission:
            permissionSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .audioSystem:
            permissionSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        default:
            permissionSettings = nil
        }
    }

    func dismissIssue() {
        issue = nil
        microphoneIssue = nil
        permissionSettings = nil
    }
}
