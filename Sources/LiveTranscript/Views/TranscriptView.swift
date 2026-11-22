import SwiftUI

struct TranscriptView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lines: [TranscriptLine]

    var body: some View {
        let rows = TranscriptPresentation.rows(for: lines)
        let newest = rows.last?.id

        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        let local = row.line.source == .microphone
                        TranscriptBubble(
                            row: row,
                            width: (geometry.size.width - 30) * 0.84,
                            isNewest: newest == row.id
                        )
                        .frame(maxWidth: .infinity, alignment: local ? .trailing : .leading)
                        .padding(.top, row.startsSource ? 13 : 6)
                        .transition(.offset(y: 10).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 2)
                .padding(.bottom, 15)
            }
            .defaultScrollAnchor(.bottom)
            .accessibilityLabel("实时对话")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: rows.map(\.id))
        }
    }
}

private struct TranscriptBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let row: TranscriptPresentation.Row
    let width: CGFloat
    let isNewest: Bool

    private var line: TranscriptLine { row.line }
    private var local: Bool { line.source == .microphone }

    var body: some View {
        let palette = ConversationPalette(colorScheme)

        VStack(alignment: local ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 7) {
                if row.startsSource {
                    Text(line.source.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(local ? palette.microphoneLabel : palette.applicationLabel)
                }
                Text(line.timestamp)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("北京时间 \(BeijingTime.dateAndTime(line.recordedAt))")
            }
            .font(.caption)
            .accessibilityHidden(true)

            GrowingTranscriptText(text: line.text, animateOnAppear: isNewest)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: local ? 15 : 5,
                        bottomLeadingRadius: 15,
                        bottomTrailingRadius: 15,
                        topTrailingRadius: local ? 5 : 15
                    )
                    .fill(local ? palette.microphone : palette.application)
                }
                .accessibilityLabel("\(line.source.title)，\(line.timestamp)，\(line.text)")
                .accessibilityValue(line.isFinal ? "" : "待定稿")
        }
        .frame(maxWidth: width, alignment: local ? .trailing : .leading)
    }
}
