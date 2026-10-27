import Foundation

/// Normalizes typed tag names the way the kernel does, so the field never offers a name the daemon would reject.
enum TagInput {
    static let maxLength = 32

    static func normalize(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("+") { name.removeFirst() }
        name = name.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        guard (1...maxLength).contains(name.count), name != CronaTagFilter.untagged,
            let first = name.unicodeScalars.first, isLetterOrDigit(first),
            name.unicodeScalars.allSatisfy({ isLetterOrDigit($0) || "-_/".unicodeScalars.contains($0) })
        else { return nil }
        return name
    }

    static func adding(_ raw: String, to tags: [String]) -> [String] {
        guard let name = normalize(raw), !tags.contains(name) else { return tags }
        return tags + [name]
    }

    /// Folds comma-separated typed text into the tag list, so text not yet added is never lost on save.
    static func committing(_ draft: String, into tags: [String]) -> [String] {
        draft.split(separator: ",").reduce(tags) { adding(String($1), to: $0) }
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}

enum TagSuggestion: Hashable {
    case existing(String)
    case create(String)

    var name: String {
        switch self {
        case .existing(let name), .create(let name): name
        }
    }
}

/// What the tag field offers for the typed text: matching tags (prefix matches first), then the typed name as new.
enum TagSuggestions {
    static let limit = 6

    static func make(draft: String, existing: [String], selected: [String]) -> [TagSuggestion] {
        let query = draft.trimmingCharacters(in: .whitespaces).lowercased()
        let available = existing.filter { !selected.contains($0) }
        guard !query.isEmpty else { return available.prefix(limit).map(TagSuggestion.existing) }
        let normalized = TagInput.normalize(query)
        let needle = normalized ?? query
        let prefixed = available.filter { $0.hasPrefix(needle) }
        let contained = available.filter { !$0.hasPrefix(needle) && $0.contains(needle) }
        var result = (prefixed + contained).prefix(limit).map(TagSuggestion.existing)
        if let normalized, !existing.contains(normalized), !selected.contains(normalized) {
            result.append(.create(normalized))
        }
        return result
    }
}
