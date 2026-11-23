import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: RecorderModel

    var body: some View {
        let lines = model.lines
        let palette = ConversationPalette(colorScheme)

        VStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 8) {
                ConversationToolbar(model: model, lines: lines)
                if let issue = model.issue ?? model.microphoneIssue {
                    notice(issue, settings: model.permissionSettings, dismiss: model.dismissIssue)
                }
                if let diskIssue = model.diskIssue {
                    notice(diskIssue)
                }
            }
            .padding(.top, 5)

            TranscriptView(lines: lines)
                .overlay {
                    if lines.isEmpty {
                        EmptyConversationArtwork(isListening: model.phase == .recording)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: lines.isEmpty)
                .background(palette.board, in: RoundedRectangle(cornerRadius: 21))
                .clipShape(RoundedRectangle(cornerRadius: 21))
                .shadow(color: palette.boardShadow, radius: 10, y: 3)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(minWidth: 390, minHeight: 455)
        .background(palette.backdrop.ignoresSafeArea())
        .containerBackground(palette.backdrop, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .alert("结束本次转写？", isPresented: $model.showsStopConfirmation) {
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("停止转写", role: .destructive, action: model.stop)
        } message: {
            Text("已转写的文字会保存在当前 Markdown 文件里。")
        }
        .onDisappear { model.stop() }
    }

    private func notice(_ message: String, settings: URL? = nil, dismiss: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let settings {
                Button("打开系统设置") { NSWorkspace.shared.open(settings) }
            }
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .accessibilityLabel("关闭提示")
            }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
