public enum TokenKind: Equatable, Sendable {
    /// A keyword or name, lowercased: `running`, `warmup`, `zone`, `x`.
    case word(String)
    /// A number and the unit written right after it: `800m`, `6x`, `250W`, `30km/h`. The unit can be empty.
    case number(Double, unit: String)
    /// A clock time in seconds, and any unit after it: `1:30`, `1:02:30`, `3:50/km`.
    case clock(Double, unit: String)
    /// A label in straight or curly quotes.
    case string(String)
    case at, dash, comma, openBrace, closeBrace
    case newline
    case end
}

public struct Token: Equatable, Sendable {
    public var kind: TokenKind
    public var range: SourceRange
}

/// Splits a script into tokens. Comments run from `#` to the end of the line.
///
/// It reads UTF-8 bytes rather than Characters: everything the language cares about is ASCII, and a few characters
/// that notes apps substitute (× for x, en and em dashes, curly quotes) are matched by their byte sequences.
struct Lexer {
    private let bytes: [UInt8]
    private var position = 0
    private(set) var diagnostics: [Diagnostic] = []

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    mutating func tokenize() -> [Token] {
        var tokens: [Token] = []
        while true {
            let token = next()
            tokens.append(token)
            if token.kind == .end { return tokens }
        }
    }

    private mutating func next() -> Token {
        skipSpacesAndComments()
        let start = position
        guard let byte = peek() else { return Token(kind: .end, range: SourceRange(start, start)) }

        let single: TokenKind? = switch byte {
        case UInt8(ascii: "\n"): .newline
        case UInt8(ascii: "@"): .at
        case UInt8(ascii: "-"): .dash
        case UInt8(ascii: ","): .comma
        case UInt8(ascii: "{"): .openBrace
        case UInt8(ascii: "}"): .closeBrace
        default: nil
        }
        if let single {
            position += 1
            return Token(kind: single, range: SourceRange(start, position))
        }
        if byte == UInt8(ascii: "\"") || matches(Self.leftCurlyQuote) {
            return string(from: start)
        }
        if isDigit(byte) {
            return number(from: start)
        }
        if isLetter(byte) {
            while let byte = peek(), isLetter(byte) || isDigit(byte) { position += 1 }
            let word = String(decoding: bytes[start..<position], as: UTF8.self).lowercased()
            return Token(kind: .word(word), range: SourceRange(start, position))
        }
        if matches(Self.multiplicationSign) {
            position += Self.multiplicationSign.count
            return Token(kind: .word("x"), range: SourceRange(start, position))
        }
        if let dash = [Self.enDash, Self.emDash].first(where: matches) {
            position += dash.count
            return Token(kind: .dash, range: SourceRange(start, position))
        }

        // Skip the whole character, not just its first byte, then carry on.
        position += 1
        while let byte = peek(), byte & 0b1100_0000 == 0b1000_0000 { position += 1 }
        let character = String(decoding: bytes[start..<position], as: UTF8.self)
        diagnostics.append(Diagnostic(.error, "unexpected character '\(character)'", at: SourceRange(start, position)))
        return next()
    }

    /// `800m`, `6x`, `2.5km`, `1:30`, `1:02:30`, `3:50/km`.
    private mutating func number(from start: Int) -> Token {
        var parts = [decimal()]
        while peek() == UInt8(ascii: ":"), let after = peek(1), isDigit(after) {
            position += 1
            parts.append(decimal())
        }
        let unitStart = position
        while let byte = peek(), isLetter(byte) || byte == UInt8(ascii: "/") { position += 1 }
        let unit = String(decoding: bytes[unitStart..<position], as: UTF8.self)
        let range = SourceRange(start, position)

        guard parts.count > 1 else { return Token(kind: .number(parts[0], unit: unit), range: range) }
        if parts.count > 3 || parts.dropFirst().contains(where: { $0 >= 60 }) {
            diagnostics.append(Diagnostic(
                .error, "not a clock time; write minutes:seconds (3:45) or hours:minutes:seconds (1:05:00)",
                at: SourceRange(start, unitStart)))
        }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return Token(kind: .clock(seconds, unit: unit), range: range)
    }

    private mutating func decimal() -> Double {
        let start = position
        while let byte = peek(), isDigit(byte) { position += 1 }
        if peek() == UInt8(ascii: "."), let after = peek(1), isDigit(after) {
            position += 1
            while let byte = peek(), isDigit(byte) { position += 1 }
        }
        return Double(String(decoding: bytes[start..<position], as: UTF8.self)) ?? 0
    }

    /// A label runs to the closing quote on the same line.
    private mutating func string(from start: Int) -> Token {
        let curly = matches(Self.leftCurlyQuote)
        position += curly ? Self.leftCurlyQuote.count : 1
        let contentStart = position
        while let byte = peek(), byte != UInt8(ascii: "\n") {
            if byte == UInt8(ascii: "\"") || matches(Self.rightCurlyQuote) {
                let content = String(decoding: bytes[contentStart..<position], as: UTF8.self)
                position += byte == UInt8(ascii: "\"") ? 1 : Self.rightCurlyQuote.count
                return Token(kind: .string(content), range: SourceRange(start, position))
            }
            position += 1
        }
        diagnostics.append(Diagnostic(
            .error, "this label is missing its closing quote", at: SourceRange(start, start + (curly ? 3 : 1)),
            fixIt: FixIt(replacing: SourceRange(position, position), with: "\"")))
        let content = String(decoding: bytes[contentStart..<position], as: UTF8.self)
        return Token(kind: .string(content), range: SourceRange(start, position))
    }

    private mutating func skipSpacesAndComments() {
        while let byte = peek() {
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r") {
                position += 1
            } else if byte == UInt8(ascii: "#") {
                while let byte = peek(), byte != UInt8(ascii: "\n") { position += 1 }
            } else {
                return
            }
        }
    }

    private func peek(_ offset: Int = 0) -> UInt8? {
        position + offset < bytes.count ? bytes[position + offset] : nil
    }

    private func matches(_ sequence: [UInt8]) -> Bool {
        bytes[position...].starts(with: sequence)
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte | 0x20) || byte == UInt8(ascii: "_")
    }

    private static let multiplicationSign: [UInt8] = [0xC3, 0x97]  // ×
    private static let enDash: [UInt8] = [0xE2, 0x80, 0x93]  // –
    private static let emDash: [UInt8] = [0xE2, 0x80, 0x94]  // —
    private static let leftCurlyQuote: [UInt8] = [0xE2, 0x80, 0x9C]  // “
    private static let rightCurlyQuote: [UInt8] = [0xE2, 0x80, 0x9D]  // ”
}
