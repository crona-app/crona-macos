import Foundation

/// The capture annotations the core parser understands, keyed by the character that starts them.
enum CaptureTrigger: Character, CaseIterable {
    case target = "#"
    case estimate = "~"
    case date = "@"
    case tag = "+"
}

/// The annotation word under the caret: its trigger, what follows it, and the whole word's range.
struct CaptureToken: Equatable {
    let trigger: CaptureTrigger
    let query: String
    let range: NSRange
}

struct CaptureSuggestion: Equatable, Hashable {
    let label: String
    let detail: String?
    let insertion: String
}

/// Finds the annotation being typed and what to offer for it, matching the core capture parser's rules.
enum CaptureAutocomplete {
    static let limit = 6
    static let estimates = ["15m", "30m", "45m", "1h", "1h30m", "2h", "3h"]
    static let dates = ["today", "tomorrow", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    static func token(in text: String, caret: Int) -> CaptureToken? {
        let string = text as NSString
        guard caret > 0, caret <= string.length else { return nil }
        var start = caret
        while start > 0, !isSpace(string.character(at: start - 1)) { start -= 1 }
        var end = caret
        while end < string.length, !isSpace(string.character(at: end)) { end += 1 }
        let word = string.substring(with: NSRange(location: start, length: caret - start))
        guard let first = word.first, let trigger = CaptureTrigger(rawValue: first) else { return nil }
        let query = String(word.dropFirst())
        guard !query.contains(where: { CaptureTrigger(rawValue: $0) != nil && $0 != "/" }) else { return nil }
        return CaptureToken(trigger: trigger, query: query, range: NSRange(location: start, length: end - start))
    }

    static func suggestions(
        for token: CaptureToken, destinations: [IssueDestination], tags: [String]
    ) -> [CaptureSuggestion] {
        let query = token.query.lowercased()
        let prefix = String(token.trigger.rawValue)
        switch token.trigger {
        case .target:
            return Array(
                destinations.filter { matchesTarget($0, query: query) }.prefix(limit).map {
                    CaptureSuggestion(
                        label: $0.label, detail: nil,
                        insertion: prefix + slug($0.repoName) + "/" + slug($0.streamName))
                })
        case .estimate:
            return plain(estimates, query: query, prefix: prefix)
        case .date:
            return plain(dates, query: query, prefix: prefix)
        case .tag:
            return plain(tags, query: query, prefix: prefix)
        }
    }

    /// Replaces the token with the suggestion and leaves the caret after a following space.
    static func apply(
        _ suggestion: CaptureSuggestion, to text: String, replacing token: CaptureToken
    ) -> (text: String, caret: Int) {
        let string = text as NSString
        let after = token.range.location + token.range.length
        let needsSpace = after >= string.length || !isSpace(string.character(at: after))
        let insertion = suggestion.insertion + (needsSpace ? " " : "")
        let replaced = string.replacingCharacters(in: token.range, with: insertion)
        let caret = token.range.location + (suggestion.insertion as NSString).length + 1
        return (replaced, caret)
    }

    private static func plain(_ options: [String], query: String, prefix: String) -> [CaptureSuggestion] {
        Array(
            options.filter { $0.lowercased().hasPrefix(query) && $0.lowercased() != query }.prefix(limit).map {
                CaptureSuggestion(label: prefix + $0, detail: nil, insertion: prefix + $0)
            })
    }

    private static func matchesTarget(_ destination: IssueDestination, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let repo = slug(destination.repoName)
        let stream = slug(destination.streamName)
        if let slash = query.firstIndex(of: "/") {
            let repoQuery = String(query[..<slash])
            let streamQuery = String(query[query.index(after: slash)...])
            return repo.hasPrefix(repoQuery) && (streamQuery.isEmpty || stream.hasPrefix(streamQuery))
        }
        return repo.hasPrefix(query) || stream.hasPrefix(query)
    }

    /// The core matches `#` targets with spaces written as `-`.
    static func slug(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }

    private static func isSpace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
