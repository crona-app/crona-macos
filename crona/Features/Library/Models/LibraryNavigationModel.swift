import Combine
import Foundation

enum LibraryDestination: String, CaseIterable, Identifiable {
    case checkIns = "Check-ins"
    case review = "Review"
    var id: Self { self }
    var icon: String { self == .checkIns ? "heart.text.square" : "chart.xyaxis.line" }
}

@MainActor
final class LibraryNavigationModel: ObservableObject {
    @Published var destination: LibraryDestination {
        didSet { defaults.set(destination.rawValue, forKey: "library.destination") }
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        destination =
            defaults.string(forKey: "library.destination").flatMap(LibraryDestination.init(rawValue:)) ?? .checkIns
    }
}
