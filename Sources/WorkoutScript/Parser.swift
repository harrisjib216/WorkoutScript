/// Where each step of a compiled workout came from, so later checks can point at the right text.
public struct SourceMap: Hashable, Sendable {
    public var header: SourceRange?
    public var steps: [StepPath: StepSpans] = [:]
}

/// The position of a step in a workout.
public enum StepPath: Hashable, Sendable {
    case warmup
    case interval(block: Int, index: Int)
    case cooldown
}

public struct StepSpans: Hashable, Sendable {
    public var step: SourceRange
    public var goal: SourceRange?
    public var alert: SourceRange?
}

/// A recursive descent parser that builds the `Workout` directly, reporting errors as it goes.
///
/// Every statement fits on one line, except a repeat's `{ }` block. After an error the parser skips to the end of the
/// line and carries on, so one typo produces one diagnostic instead of a cascade.
struct Parser {
    private struct Header {
        var activity: Activity
        var location: Location?
        var name: String?
    }

    private struct ParsedStep {
        var step: Step
        var spans: StepSpans
    }

    private enum Statement {
        case warmup(ParsedStep)
        case cooldown(ParsedStep)
        case block(Block, spans: [StepSpans])
    }

    /// A number or clock with its unit, which may have been written as a separate word: `10 min`.
    private struct Quantity {
        var value: Double
        var unit: String
        var isClock: Bool
        var range: SourceRange
        var unitRange: SourceRange
    }

    private let text: String
    private let tokens: [Token]
    private var index = 0
    private var activity: Activity?
    private(set) var diagnostics: [Diagnostic]
    private(set) var sourceMap = SourceMap()

    init(text: String, tokens: [Token], diagnostics: [Diagnostic] = []) {
        self.text = text
        self.tokens = tokens
        self.diagnostics = diagnostics
    }

    // MARK: - Script

    mutating func parseWorkout() -> Workout? {
        skipSeparators()
        let header = parseHeader()
        activity = header?.activity
        var workout = Workout(activity: header?.activity ?? .running, location: header?.location, name: header?.name)
        var warmupRange: SourceRange?
        var cooldownRange: SourceRange?

        while true {
            skipSeparators()
            if current.kind == .end { break }
            let start = current.range.lowerBound
            let statement = parseStatement()
            let range = SourceRange(start, previousEnd)
            if statement == nil { skipLine() } else { expectLineEnd() }
            guard let statement else { continue }

            if let cooldownRange {
                error("nothing can come after the cooldown", at: range, note: ("the cooldown is here", cooldownRange))
                continue
            }
            switch statement {
            case .warmup(let parsed):
                if let warmupRange {
                    error("this workout already has a warmup", at: range, note: ("the first one is here", warmupRange))
                } else if !workout.blocks.isEmpty {
                    error("the warmup has to come before the intervals", at: range)
                } else {
                    workout.warmup = parsed.step
                    warmupRange = range
                    sourceMap.steps[.warmup] = parsed.spans
                }
            case .cooldown(let parsed):
                workout.cooldown = parsed.step
                cooldownRange = range
                sourceMap.steps[.cooldown] = parsed.spans
            case .block(let block, let spans):
                for (position, span) in spans.enumerated() {
                    sourceMap.steps[.interval(block: workout.blocks.count, index: position)] = span
                }
                workout.blocks.append(block)
            }
        }

        if header != nil, workout.warmup == nil, workout.blocks.isEmpty, workout.cooldown == nil,
           !diagnostics.contains(where: { $0.severity == .error }) {
            error("this workout has no steps yet; add one, like 6x 400m", at: sourceMap.header ?? current.range)
        }
        return header == nil ? nil : workout
    }

    /// `running outdoor "Track 800s"`
    private mutating func parseHeader() -> Header? {
        guard case .word(let word) = current.kind, !Self.statementWords.contains(word) else {
            error(
                "a script starts with its activity, like running outdoor", at: current.range,
                fixIt: FixIt(replacing: SourceRange(current.range.lowerBound, current.range.lowerBound),
                             with: "running outdoor\n"))
            return nil
        }
        let start = current.range
        advance()
        guard let activity = Activity(rawValue: word) else {
            unknown("activity", word, at: start, candidates: Activity.allCases.map(\.rawValue))
            skipLine()
            return nil
        }
        var location: Location?
        if case .word(let word) = current.kind {
            location = Location(rawValue: word)
            if location == nil {
                unknown("location", word, at: current.range, candidates: Location.allCases.map(\.rawValue))
            }
            advance()
        }
        var name: String?
        if case .string(let text) = current.kind {
            name = text
            advance()
        }
        sourceMap.header = SourceRange(start.lowerBound, previousEnd)
        expectLineEnd()
        return Header(activity: activity, location: location, name: name)
    }

    private mutating func parseStatement() -> Statement? {
        let start = current.range.lowerBound
        switch current.kind {
        case .word("warmup"):
            advance()
            return parseStep(from: start, afterKeyword: true).map(Statement.warmup)
        case .word("cooldown"):
            advance()
            return parseStep(from: start, afterKeyword: true).map(Statement.cooldown)
        case .closeBrace:
            error("there's no repeat for this } to close", at: current.range)
            return nil
        default:
            if isRepeatStart { return parseRepeat() }
            guard let (interval, spans) = parseInterval() else { return nil }
            return .block(Block(intervals: [interval]), spans: [spans])
        }
    }

    // MARK: - Repeats

    /// `6x 400m`, or a block: `6x { 800m @ 4:00/km, recover 400m }`.
    private var isRepeatStart: Bool {
        switch current.kind {
        case .number(_, let unit) where unit.lowercased() == "x": true
        case .number(_, ""): peek().kind == .word("x")
        default: false
        }
    }

    private mutating func parseRepeat() -> Statement? {
        guard case .number(let count, let unit) = current.kind else { return nil }
        let countStart = current.range.lowerBound
        advance()
        if unit.isEmpty { advance() }
        let countRange = SourceRange(countStart, previousEnd)
        var iterations = Int(count)
        if count < 1 || count != count.rounded() {
            error("a repeat count is a whole number, 1 or more", at: countRange)
            iterations = 1
        }

        var intervals: [Interval] = []
        var spans: [StepSpans] = []
        // A block whose steps all failed already has its errors; don't add "no steps" on top.
        var hadErrors = false
        if current.kind == .openBrace {
            let brace = current.range
            advance()
            while true {
                skipSeparators()
                if current.kind == .closeBrace {
                    advance()
                    break
                }
                if current.kind == .end {
                    error(
                        "this repeat is missing its closing }", at: brace,
                        fixIt: FixIt(replacing: SourceRange(previousEnd, previousEnd), with: "\n}"))
                    break
                }
                if isRepeatStart {
                    error("repeats can't be nested; WorkoutKit runs one level of repeats", at: current.range)
                    hadErrors = true
                    skipLine(insideBlock: true)
                    continue
                }
                if case .word(let word) = current.kind, word == "warmup" || word == "cooldown" {
                    error("the \(word) goes outside the repeat", at: current.range)
                    hadErrors = true
                    skipLine(insideBlock: true)
                    continue
                }
                guard let (interval, span) = parseInterval() else {
                    hadErrors = true
                    skipLine(insideBlock: true)
                    continue
                }
                intervals.append(interval)
                spans.append(span)
                switch current.kind {
                case .newline, .comma, .closeBrace, .end: break
                default:
                    unexpected(current)
                    skipLine(insideBlock: true)
                }
            }
        } else {
            guard current.kind != .newline, current.kind != .end else {
                error("a repeat needs steps, like 6x 400m or 6x { 400m, recover 200m }", at: countRange)
                return nil
            }
            guard let (interval, span) = parseInterval() else { return nil }
            intervals = [interval]
            spans = [span]
        }

        guard !intervals.isEmpty else {
            if !hadErrors { error("this repeat has no steps", at: countRange) }
            return nil
        }
        return .block(Block(iterations: iterations, intervals: intervals), spans: spans)
    }

    // MARK: - Steps

    /// `800m @ 4:00/km "Fast"`, `recover 2min`, `work open`.
    private mutating func parseInterval() -> (Interval, StepSpans)? {
        let start = current.range.lowerBound
        var purpose = Interval.Purpose.work
        var hasKeyword = false
        if case .word(let word) = current.kind {
            if word == "work" {
                hasKeyword = true
            } else if Self.recoveryWords.contains(word) {
                purpose = .recovery
                hasKeyword = true
            }
            if hasKeyword {
                advance()
            } else if !Self.stepWords.contains(word) {
                unknown("step", word, at: current.range, candidates: Self.statementWords)
                return nil
            }
        }
        guard let parsed = parseStep(from: start, afterKeyword: hasKeyword) else { return nil }
        return (Interval(purpose, parsed.step), parsed.spans)
    }

    /// A goal, then `@` and a target, then a label in quotes. Each part is optional; no goal means an open goal.
    private mutating func parseStep(from start: Int, afterKeyword: Bool) -> ParsedStep? {
        let first = index
        var spans = StepSpans(step: SourceRange(start, start))
        var goal = Goal.open
        switch current.kind {
        case .word("open"):
            spans.goal = current.range
            advance()
        case .number, .clock:
            guard let (parsed, range) = parseGoal() else { return nil }
            goal = parsed
            spans.goal = range
        default:
            break
        }

        var alert: Alert?
        if current.kind == .at {
            advance()
            guard let (parsed, range) = parseAlert() else { return nil }
            alert = parsed
            spans.alert = range
        }

        var label: String?
        if case .string(let text) = current.kind {
            label = text
            advance()
        }

        if index == first, !afterKeyword {
            error("expected a step, like 800m @ 4:00/km", at: current.range)
            return nil
        }
        spans.step = SourceRange(start, previousEnd)
        return ParsedStep(step: Step(goal: goal, alert: alert, label: label), spans: spans)
    }

    /// `15min`, `90s`, `1:30`, `800m`, `5k`, `300kcal`, `100m in 1:45`.
    private mutating func parseGoal() -> (Goal, SourceRange)? {
        let quantity = takeQuantity(units: Self.goalUnitWords)
        let symbol = quantity.unit.lowercased()
        let range = quantity.range

        if quantity.isClock {
            if symbol.isEmpty { return (.time(quantity.value, .seconds), range) }
            error("\(source(range)) is a pace; pace targets go after @, like 1km @ 4:00/km", at: range)
            return nil
        }
        guard quantity.value > 0 else {
            error("a goal has to be more than zero", at: range)
            return nil
        }
        if let unit = Self.timeUnits[symbol] {
            return (.time(quantity.value, unit), range)
        }
        if let unit = Self.distanceUnits[symbol] {
            if current.kind == .word("in") {
                advance()
                guard let seconds = parseDuration() else { return nil }
                return (.poolSwim(quantity.value, unit, seconds: seconds), SourceRange(range.lowerBound, previousEnd))
            }
            if unit == .meters, quantity.value <= 30, activity != .swimming {
                diagnostics.append(Diagnostic(
                    .warning, "\(source(range)) is \(format(quantity.value)) meters; for minutes, write min",
                    at: range, fixIt: FixIt(replacing: quantity.unitRange, with: "min")))
            }
            return (.distance(quantity.value, unit), range)
        }
        if let unit = Self.energyUnits[symbol] {
            return (.energy(quantity.value, unit), range)
        }
        if symbol.isEmpty {
            error("\(source(range)) needs a unit: a time (10min), a distance (2km) or open", at: range)
        } else if Self.targetUnits.contains(symbol) {
            error("\(source(range)) is a target, not a goal; targets go after @", at: range)
        } else {
            unknown("unit", quantity.unit, at: quantity.unitRange, candidates: Self.goalUnitNames)
        }
        return nil
    }

    /// The time in `100m in 1:45`: a clock, or a number with a time unit.
    private mutating func parseDuration() -> Double? {
        switch current.kind {
        case .clock(let seconds, ""):
            advance()
            return seconds
        case .number:
            let quantity = takeQuantity(units: Array(Self.timeUnits.keys))
            if let unit = Self.timeUnits[quantity.unit.lowercased()] { return quantity.value * unit.seconds }
            error("expected a time after in, like 100m in 1:45", at: quantity.range)
            return nil
        default:
            error("expected a time after in, like 100m in 1:45", at: current.range)
            return nil
        }
    }

    // MARK: - Targets

    /// `4:00/km`, `3:50-4:00/km`, `30km/h`, `140-155bpm`, `250W`, `170spm`, `zone 2`, `power zone 3`, `avg 4:30/km`.
    private mutating func parseAlert() -> (Alert, SourceRange)? {
        let start = current.range.lowerBound
        var averageRange: SourceRange?
        if current.kind == .word("avg") || current.kind == .word("average") {
            averageRange = current.range
            advance()
        }

        var alert: Alert
        switch current.kind {
        case .word("zone"):
            advance()
            guard let zone = parseZone() else { return nil }
            guard (1...5).contains(zone) else {
                error("heart rate zones run from 1 to 5", at: tokens[index - 1].range)
                return nil
            }
            alert = .heartRateZone(zone)
        case .word("power"):
            advance()
            guard current.kind == .word("zone") else {
                error("expected zone after power, like power zone 3", at: current.range)
                return nil
            }
            advance()
            guard let zone = parseZone() else { return nil }
            alert = .powerZone(zone)
        case .number, .clock:
            guard let parsed = parseTarget() else { return nil }
            alert = parsed
        default:
            error("expected a target after @, like 4:30/km, 140-150bpm, zone 2 or 250W", at: current.range)
            return nil
        }

        if let averageRange {
            switch alert {
            case .pace(let target, let unit, _): alert = .pace(target, unit, .average)
            case .speed(let target, let unit, _): alert = .speed(target, unit, .average)
            case .power(let target, _): alert = .power(target, .average)
            default:
                error("avg works with pace, speed and power targets", at: averageRange)
                return nil
            }
        }
        return (alert, SourceRange(start, previousEnd))
    }

    private mutating func parseZone() -> Int? {
        guard case .number(let value, "") = current.kind, value >= 1, value == value.rounded() else {
            error("expected a zone number, like zone 2", at: current.range)
            return nil
        }
        advance()
        return Int(value)
    }

    /// A value or a range, with the unit on either end: `140-155bpm`, `140bpm-155`, `3:50-4:00/km`.
    private mutating func parseTarget() -> Alert? {
        let low = takeQuantity(units: Self.targetUnitWords)
        var high: Quantity?
        if current.kind == .dash {
            advance()
            switch current.kind {
            case .number, .clock:
                high = takeQuantity(units: Self.targetUnitWords)
            default:
                error("expected the top of the range after -", at: current.range)
                return nil
            }
        }
        let range = SourceRange(low.range.lowerBound, (high ?? low).range.upperBound)
        let symbols = [high?.unit, low.unit].compactMap { $0?.lowercased() }.filter { !$0.isEmpty }
        guard let symbol = symbols.first else {
            error("this target needs a unit: /km or /mi for pace, km/h or mph for speed, bpm, W, spm or rpm", at: range)
            return nil
        }
        guard symbols.allSatisfy({ $0 == symbol }) else {
            error("both ends of a range need the same unit", at: range)
            return nil
        }

        let isPace = Self.paceUnits[symbol] != nil
        guard Self.targetUnits.contains(symbol) else {
            if Self.goalUnitWords.contains(symbol) {
                error("\(source(range)) is a goal, not a target; the goal goes before @", at: range)
            } else {
                let unitRange = (high?.unit.isEmpty == false ? high! : low).unitRange
                unknown("unit", (high?.unit.isEmpty == false ? high! : low).unit, at: unitRange,
                        candidates: Self.targetUnitNames)
            }
            return nil
        }

        // Pace reads minutes and seconds; a plain number is minutes, so 4.5/km is 4:30/km.
        let ends = [low] + (high.map { [$0] } ?? [])
        if !isPace, let clock = ends.first(where: \.isClock) {
            error("\(source(clock.range)) is a clock time; only pace targets use minutes:seconds", at: clock.range)
            return nil
        }
        let values = ends.map { isPace && !$0.isClock ? $0.value * 60 : $0.value }
        guard values.allSatisfy({ $0 > 0 }) else {
            error("a target has to be more than zero", at: range)
            return nil
        }
        let target: Target = values.count == 1 ? .value(values[0]) : .range(values.min()!...values.max()!)

        if let unit = Self.paceUnits[symbol] { return .pace(target, unit, .current) }
        if let unit = Self.speedUnits[symbol] { return .speed(target, unit, .current) }
        if let unit = Self.cadenceUnits[symbol] { return .cadence(target, unit) }
        if symbol == "w" { return .power(target, .current) }
        guard case .range(let beats) = target else {
            let middle = Int(values[0])
            let suggestion = "\(middle - 5)-\(middle + 5)bpm"
            error(
                "heart rate targets need a range or a zone, like \(suggestion) or zone 2", at: range,
                fixIt: FixIt(replacing: range, with: suggestion))
            return nil
        }
        return .heartRate(beats)
    }

    /// Reads a number or clock, plus a unit written as a separate word right after it (`10 min`, `150 W`).
    private mutating func takeQuantity(units: [String]) -> Quantity {
        let token = current
        advance()
        var quantity: Quantity
        switch token.kind {
        case .number(let value, let unit):
            let unitStart = token.range.upperBound - unit.utf8.count
            quantity = Quantity(
                value: value, unit: unit, isClock: false, range: token.range,
                unitRange: SourceRange(unitStart, token.range.upperBound))
        case .clock(let seconds, let unit):
            let unitStart = token.range.upperBound - unit.utf8.count
            quantity = Quantity(
                value: seconds, unit: unit, isClock: true, range: token.range,
                unitRange: SourceRange(unitStart, token.range.upperBound))
        default:
            return Quantity(value: 0, unit: "", isClock: false, range: token.range, unitRange: token.range)
        }
        if quantity.unit.isEmpty, case .word(let word) = current.kind, units.contains(word) {
            quantity.unit = word
            quantity.unitRange = current.range
            quantity.range = quantity.range.joined(with: current.range)
            advance()
        }
        return quantity
    }

    // MARK: - Errors and recovery

    private mutating func expectLineEnd() {
        switch current.kind {
        case .newline, .end: return
        case .comma: advance()
        default:
            unexpected(current)
            skipLine()
        }
    }

    private mutating func unexpected(_ token: Token) {
        let message = switch token.kind {
        case .number, .clock: "a step has one goal; put the next step on its own line"
        case .at: "a step has one target"
        case .string: "a step has one label"
        case .openBrace: "a block starts with a repeat count, like 6x {"
        case .closeBrace: "there's no repeat for this } to close"
        default: "unexpected '\(source(token.range))'"
        }
        error(message, at: token.range)
    }

    /// Skips to the end of the line, stepping over any nested `{ }` so a broken block is skipped whole.
    /// Inside a block it also stops before the `}` that closes the block.
    private mutating func skipLine(insideBlock: Bool = false) {
        var depth = 0
        while true {
            switch current.kind {
            case .end:
                return
            case .newline where depth == 0:
                return
            case .closeBrace where depth == 0:
                if insideBlock { return }
            case .openBrace:
                depth += 1
            case .closeBrace:
                depth -= 1
            default:
                break
            }
            advance()
        }
    }

    private mutating func skipSeparators() {
        while current.kind == .newline || current.kind == .comma { advance() }
    }

    private mutating func unknown(_ kind: String, _ word: String, at range: SourceRange, candidates: [String]) {
        if let suggestion = closest(to: word, in: candidates) {
            error("unknown \(kind) '\(word)'; did you mean '\(suggestion)'?", at: range,
                  fixIt: FixIt(replacing: range, with: suggestion))
        } else {
            error("unknown \(kind) '\(word)'", at: range)
        }
    }

    private mutating func error(
        _ message: String, at range: SourceRange, fixIt: FixIt? = nil, note: (String, SourceRange)? = nil
    ) {
        var diagnostic = Diagnostic(.error, message, at: range, fixIt: fixIt)
        if let note { diagnostic.notes = [Diagnostic.Note(note.0, at: note.1)] }
        diagnostics.append(diagnostic)
    }

    // MARK: - Tokens

    private var current: Token { tokens[index] }

    private func peek() -> Token { tokens[min(index + 1, tokens.count - 1)] }

    private var previousEnd: Int { index > 0 ? tokens[index - 1].range.upperBound : 0 }

    private mutating func advance() {
        if index < tokens.count - 1 { index += 1 }
    }

    private func source(_ range: SourceRange) -> String {
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: range.lowerBound)
        let end = utf8.index(utf8.startIndex, offsetBy: range.upperBound)
        return String(text[start..<end])
    }

    // MARK: - Vocabulary

    private static let statementWords = ["warmup", "cooldown", "work", "recover", "open"]
    private static let stepWords: Set = ["work", "recover", "recovery", "rest", "open", "x"]
    private static let recoveryWords: Set = ["recover", "recovery", "rest"]

    private static let timeUnits: [String: TimeUnit] = [
        "s": .seconds, "sec": .seconds, "secs": .seconds, "min": .minutes, "mins": .minutes,
        "h": .hours, "hr": .hours, "hrs": .hours,
    ]
    private static let distanceUnits: [String: DistanceUnit] = [
        "m": .meters, "km": .kilometers, "k": .kilometers, "mi": .miles, "yd": .yards,
    ]
    private static let energyUnits: [String: EnergyUnit] = ["kcal": .kilocalories, "cal": .kilocalories, "kj": .kilojoules]
    private static let paceUnits: [String: PaceUnit] = ["/km": .perKilometer, "/mi": .perMile]
    private static let speedUnits: [String: SpeedUnit] = [
        "km/h": .kilometersPerHour, "kph": .kilometersPerHour, "mph": .milesPerHour, "m/s": .metersPerSecond,
    ]
    private static let cadenceUnits: [String: CadenceUnit] = ["spm": .stepsPerMinute, "rpm": .revolutionsPerMinute]

    private static let goalUnitWords = Array(timeUnits.keys) + Array(distanceUnits.keys) + Array(energyUnits.keys)
    private static let targetUnitWords = ["kph", "mph", "bpm", "w", "spm", "rpm"]
    private static let targetUnits: Set = Set(paceUnits.keys).union(speedUnits.keys).union(cadenceUnits.keys)
        .union(["bpm", "w"])
    private static let goalUnitNames = ["s", "min", "h", "m", "km", "mi", "yd", "kcal", "kJ"]
    private static let targetUnitNames = ["/km", "/mi", "km/h", "mph", "m/s", "bpm", "W", "spm", "rpm"]
}

/// The candidate closest to `word`, if it is close enough to be a typo: at most two edits, counting a swap of two
/// neighboring letters as one edit.
func closest(to word: String, in candidates: [String]) -> String? {
    let word = Array(word.lowercased())
    var best: (candidate: String, distance: Int)?
    for candidate in candidates {
        let distance = editDistance(word, Array(candidate.lowercased()))
        if distance <= min(2, max(word.count - 1, 1)), distance < (best?.distance ?? .max) {
            best = (candidate, distance)
        }
    }
    return best?.candidate
}

/// Optimal string alignment distance: insertions, deletions, substitutions and adjacent swaps.
private func editDistance(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
    var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { table[i][0] = i }
    for j in 0...b.count { table[0][j] = j }
    for i in 1...a.count {
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
            if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
            }
        }
    }
    return table[a.count][b.count]
}
