import AppKit
import SwiftUI

struct ConversationToolbar: View {
    fileprivate static let controlHeight: CGFloat = 21

    let model: RecorderModel
    let lines: [TranscriptLine]

    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: copyTranscript) {
                ToolbarButtonLabel("复制", symbol: copied ? "checkmark" : "document.on.document")
            }
            .disabled(lines.isEmpty)
            .help(copied ? "已复制" : "复制文字")

            Button {
                if let file = model.fileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
            } label: {
                ToolbarButtonLabel("访达", symbol: "folder")
            }
            .disabled(model.fileURL == nil)
            .help(model.fileURL?.lastPathComponent ?? "在访达中显示 Markdown")

            Spacer(minLength: 7)

            TranscriptionStatus(phase: model.phase)
                .help(model.phase == .preparing ? model.detail : model.phase.title)

            if model.phase.showsPauseButton {
                Button {
                    model.pauseOrResume()
                } label: {
                    ToolbarButtonLabel(
                        model.phase.offersResume ? "继续" : "暂停",
                        symbol: model.phase.offersResume ? "play.fill" : "pause.fill"
                    )
                }
                .disabled(!model.phase.canPauseOrResume)
                .help(model.phase.offersResume ? "继续转写" : "暂停转写")
            }

            Button {
                if model.phase == .idle { copied = false }
                model.toggle()
            } label: {
                ToolbarButtonLabel(
                    model.phase.showsPauseButton ? "停止" : model.phase.buttonTitle,
                    symbol: model.phase.buttonSymbol
                )
            }
            .disabled(model.phase == .stopping)
            .accessibilityLabel(model.phase.buttonTitle)
            .help("⌘ 回车")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .onChange(of: lines.isEmpty) { copied = false }
    }

    private func copyTranscript() {
        let text = lines.map { "[\($0.timestamp)] \($0.source.title)：\($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ToolbarButtonLabel: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .frame(height: 17)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct TranscriptionStatus: View {
    let phase: RecorderModel.Phase

    private var background: Color {
        switch phase {
        case .recording:
            Color(red: 0.73, green: 0.15, blue: 0.19)
        case .pausing, .paused:
            Color(red: 0.51, green: 0.34, blue: 0.13)
        case .preparing, .resuming:
            Color(red: 0.27, green: 0.36, blue: 0.46)
        case .idle, .stopping:
            Color(red: 0.29, green: 0.32, blue: 0.36)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if phase.isBusy {
                    ProgressView().controlSize(.mini).scaleEffect(0.76)
                        .tint(.white)
                } else {
                    Circle()
                        .fill(.white.opacity(phase == .idle ? 0.58 : 1))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 10, height: 12)
            .accessibilityHidden(true)

            Text(phase.title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(width: 72, height: ConversationToolbar.controlHeight)
        .background(background, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
