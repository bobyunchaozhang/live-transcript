import Testing
@testable import LiveTranscript

@Test func appendingTextPreservesAnInFlightFade() throws {
    var transition = TranscriptTextTransition(text: "今天", revealAt: 1)
    transition.update(to: "今天开会", at: 1.08)

    #expect(transition.current.text == "今天开会")
    #expect(transition.departures.isEmpty)
    #expect(transition.current.reveals.map(\.range) == [0..<2, 2..<4])

    let existing = try #require(transition.current.reveals.first)
    let appended = try #require(transition.current.reveals.last)
    #expect(existing.startedAt == 1)
    #expect(existing.opacity(at: 1.08, glyph: 1) > 0)
    #expect(existing.opacity(at: 1.08, glyph: 1) < 1)
    #expect(appended.opacity(at: 1.08, glyph: 0) == 0)
    #expect(appended.opacity(at: 1.18, glyph: 0) > appended.opacity(at: 1.18, glyph: 1))
}

@Test func correctingTextCrossfadesOnlyTheChangedTail() throws {
    var transition = TranscriptTextTransition(text: "确认明天", revealAt: 1)
    transition.update(to: "确认今天", at: 1.14)
    transition.update(to: "确认今日", at: 1.21)

    #expect(transition.current.text == "确认今日")
    #expect(transition.current.reveals.map(\.range) == [0..<2, 2..<3, 3..<4])
    #expect(transition.departures.map(\.prefixLength) == [2, 3])
    #expect(transition.departures.map(\.snapshot.text) == ["确认明天", "确认今天"])
    let first = try #require(transition.departures.first)
    #expect(first.opacity(at: 1.14) == 1)
    #expect(first.opacity(at: 1.21) > 0)
    #expect(first.opacity(at: 1.21) < 1)
    #expect(first.opacity(at: 1.35) == 0)

    transition.update(to: "确认", at: 2)
    #expect(transition.current.reveals.isEmpty)
    #expect(transition.departures.map(\.prefixLength) == [2])
    #expect(transition.endsAt == transition.departures.first?.endsAt)
}
