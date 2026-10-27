import Combine
import Foundation

/// The one day the Issues, Habits, Wellbeing and Stats tabs show. It never goes past today.
@MainActor
final class PopoverDayModel: ObservableObject {
    private let today: () -> String

    @Published private(set) var selectedDate: String
    var onChange: ((String) -> Void)?

    init(today: @escaping () -> String) {
        self.today = today
        self.selectedDate = today()
    }

    var isToday: Bool { selectedDate >= today() }
    var canShowNextDay: Bool { selectedDate < today() }

    func showPreviousDay() {
        select(CronaCalendarDate.adding(days: -1, to: selectedDate) ?? selectedDate)
    }

    func showNextDay() {
        guard canShowNextDay else { return }
        select(CronaCalendarDate.adding(days: 1, to: selectedDate) ?? selectedDate)
    }

    func showToday() {
        select(today())
    }

    func select(_ date: String) {
        guard !date.isEmpty else { return }
        let clamped = min(date, today())
        guard clamped != selectedDate else { return }
        selectedDate = clamped
        onChange?(clamped)
    }

    func handleDayStart(date: String, previousDate: String) {
        guard selectedDate == previousDate else { return }
        select(date)
    }
}
