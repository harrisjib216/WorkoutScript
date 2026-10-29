/// A half-open range of UTF-8 offsets into a script.
public struct SourceRange: Hashable, Sendable {
    public var lowerBound: Int
    public var upperBound: Int

    public init(_ lowerBound: Int, _ upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    /// The smallest range that covers both.
    public func joined(with other: SourceRange) -> SourceRange {
        SourceRange(min(lowerBound, other.lowerBound), max(upperBound, other.upperBound))
    }
}

/// A script's text plus a table of where each line starts, for turning offsets into lines and columns.
public struct SourceFile: Sendable {
    public let name: String
    public let text: String
    private let lineStarts: [Int]

    public init(name: String = "<input>", text: String) {
        self.name = name
        self.text = text
        var starts = [0]
        for (offset, byte) in text.utf8.enumerated() where byte == UInt8(ascii: "\n") {
            starts.append(offset + 1)
        }
        lineStarts = starts
    }

    /// One-based line and column. Columns count characters, so carets line up under non-ASCII labels too.
    public func position(of offset: Int) -> (line: Int, column: Int) {
        let line = lineIndex(of: offset)
        let start = index(at: lineStarts[line])
        return (line + 1, text[start..<index(at: offset)].count + 1)
    }

    /// The text of a one-based line, without its newline.
    public func line(_ number: Int) -> Substring {
        let start = index(at: lineStarts[number - 1])
        let end = number < lineStarts.count ? index(at: lineStarts[number] - 1) : text.endIndex
        return text[start..<end]
    }

    /// String indices for a range, for highlighting or selecting it in a text view.
    public func indices(of range: SourceRange) -> Range<String.Index> {
        index(at: range.lowerBound)..<index(at: range.upperBound)
    }

    private func index(at offset: Int) -> String.Index {
        text.utf8.index(text.startIndex, offsetBy: min(max(offset, 0), text.utf8.count))
    }

    private func lineIndex(of offset: Int) -> Int {
        // The last line that starts at or before the offset.
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }
}

/// An error, warning or note about a range of a script, with an optional suggested edit.
public struct Diagnostic: Hashable, Sendable {
    public enum Severity: String, Sendable {
        case error, warning, note
    }

    public var severity: Severity
    public var message: String
    public var range: SourceRange
    public var fixIt: FixIt?
    /// Other places in the script that explain the diagnostic, such as the first warmup when there are two.
    public var notes: [Note] = []

    public init(_ severity: Severity, _ message: String, at range: SourceRange, fixIt: FixIt? = nil) {
        self.severity = severity
        self.message = message
        self.range = range
        self.fixIt = fixIt
    }

    public struct Note: Hashable, Sendable {
        public var message: String
        public var range: SourceRange

        public init(_ message: String, at range: SourceRange) {
            self.message = message
            self.range = range
        }
    }
}

/// Replace `range` with `replacement`. An empty range is an insertion.
public struct FixIt: Hashable, Sendable {
    public var range: SourceRange
    public var replacement: String

    public init(replacing range: SourceRange, with replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

extension Diagnostic {
    /// The diagnostic laid out the way swiftc prints one: location, message, the line, a caret under the range,
    /// and the suggested replacement under that.
    public func rendered(in file: SourceFile) -> String {
        var output = Self.render(severity, message, range, fixIt, in: file)
        for note in notes {
            output += "\n" + Self.render(.note, note.message, note.range, nil, in: file)
        }
        return output
    }

    private static func render(
        _ severity: Severity, _ message: String, _ range: SourceRange, _ fixIt: FixIt?, in file: SourceFile
    ) -> String {
        let (line, column) = file.position(of: range.lowerBound)
        let text = file.line(line)
        let end = file.position(of: range.upperBound)
        let width = end.line == line ? max(end.column - column, 1) : max(text.count - column + 1, 1)
        let indent = String(repeating: " ", count: column - 1)
        var output = "\(file.name):\(line):\(column): \(severity.rawValue): \(message)\n"
        output += "\(text)\n"
        output += indent + "^" + String(repeating: "~", count: width - 1)
        if let fixIt, !fixIt.replacement.contains("\n") {
            let fixColumn = file.position(of: fixIt.range.lowerBound).column
            output += "\n" + String(repeating: " ", count: fixColumn - 1) + fixIt.replacement
        }
        return output
    }
}
