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

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}
