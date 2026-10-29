import Testing
@testable import WorkoutScript

@Suite struct LexerTests {
    private func kinds(_ text: String) -> [TokenKind] {
        var lexer = Lexer(text)
        return lexer.tokenize().map(\.kind)
    }

    @Test func numbersCarryTheirUnits() {
        #expect(kinds("6x { 800m @ 3:50-4:00/km }") == [
            .number(6, unit: "x"), .openBrace, .number(800, unit: "m"), .at,
            .clock(230, unit: ""), .dash, .clock(240, unit: "/km"), .closeBrace, .end,
        ])
        #expect(kinds("2.5km 30km/h 250W") == [
            .number(2.5, unit: "km"), .number(30, unit: "km/h"), .number(250, unit: "W"), .end,
        ])
    }

    @Test func clocksAreSeconds() {
        #expect(kinds("1:30 1:02:30 3:50.5") == [.clock(90, unit: ""), .clock(3750, unit: ""), .clock(230.5, unit: ""), .end])
    }

    @Test func wordsAreLowercased() {
        #expect(kinds("Running OUTDOOR") == [.word("running"), .word("outdoor"), .end])
    }

    @Test func commentsRunToTheEndOfTheLine() {
        #expect(kinds("warmup # easy\ncooldown") == [.word("warmup"), .newline, .word("cooldown"), .end])
    }

    @Test func notesAppCharactersAreUnderstood() {
        // × for x, an en dash for -, and curly quotes, the way notes apps rewrite them.
        #expect(kinds("6 × 400m @ 3:50–4:00/km “Fast”") == [
            .number(6, unit: ""), .word("x"), .number(400, unit: "m"), .at,
            .clock(230, unit: ""), .dash, .clock(240, unit: "/km"), .string("Fast"), .end,
        ])
    }

    @Test func badInputIsReportedAndSkipped() {
        var lexer = Lexer("10min ; 5:75")
        let tokens = lexer.tokenize().map(\.kind)
        #expect(tokens == [.number(10, unit: "min"), .clock(375, unit: ""), .end])
        #expect(lexer.diagnostics.map(\.message) == [
            "unexpected character ';'",
            "not a clock time; write minutes:seconds (3:45) or hours:minutes:seconds (1:05:00)",
        ])
    }

    @Test func labelsNeedAClosingQuote() {
        var lexer = Lexer("800m \"Fast\n")
        #expect(lexer.tokenize().map(\.kind) == [.number(800, unit: "m"), .string("Fast"), .newline, .end])
        #expect(lexer.diagnostics.first?.message == "this label is missing its closing quote")
    }
}
