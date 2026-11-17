import Foundation

enum DurationInput {
    static func minutes(_ text: String, maximum: Int = Int.max / 60) -> Int? {
        guard case let .success(value?) = FlexibleDurationParser.optionalMinutes(text),
              value <= maximum else { return nil }
        return value
    }
}
