import Foundation

/// The TUI's tag filter query: `+a` keeps items tagged `a` (several are OR), `-b` drops items tagged `b`,
/// and `untagged` stands for items with no tags.
struct CronaTagFilter: Equatable {
    static let untagged = "untagged"

    var any: [String] = []
    var none: [String] = []

    init(any: [String] = [], none: [String] = []) {
        self.any = any
        self.none = none
    }

    init(query: String) {
        for field in query.lowercased().split(whereSeparator: \.isWhitespace) where field.count > 1 {
            let name = String(field.dropFirst())
            switch field.first {
            case "+": if !any.contains(name) { any.append(name) }
            case "-": if !none.contains(name) { none.append(name) }
            default: break
            }
        }
    }

    var query: String {
        (any.map { "+\($0)" } + none.map { "-\($0)" }).joined(separator: " ")
    }

    var isEmpty: Bool { any.isEmpty && none.isEmpty }

    /// Names that are neither known tags nor `untagged` are ignored, so a stale saved filter never hides everything.
    func matches(_ tags: [String], known: Set<String>) -> Bool {
        let relevant = { (name: String) in name == Self.untagged || known.contains(name) }
        let has = { (name: String) in name == Self.untagged ? tags.isEmpty : tags.contains(name) }
        let anyNames = any.filter(relevant)
        if !anyNames.isEmpty && !anyNames.contains(where: has) { return false }
        return !none.filter(relevant).contains(where: has)
    }

    mutating func toggleShow(_ name: String) {
        none.removeAll { $0 == name }
        if let index = any.firstIndex(of: name) { any.remove(at: index) } else { any.append(name) }
    }

    mutating func toggleHide(_ name: String) {
        any.removeAll { $0 == name }
        if let index = none.firstIndex(of: name) { none.remove(at: index) } else { none.append(name) }
    }
}
