import Foundation

/// Batches bursts and permits only one event-driven refresh batch at a time.
@MainActor
final class StatsRefreshQueue {
    private var dates: Set<String> = []
    private var reloadCalendar = false
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func enqueue(dates: Set<String>, reloadCalendar: Bool = false,
                 perform: @escaping @MainActor (Set<String>, Bool) async -> Void) {
        self.dates.formUnion(dates)
        self.reloadCalendar = self.reloadCalendar || reloadCalendar
        guard task == nil else { return }
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token { task = nil } }
            repeat {
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                guard generation == token, !Task.isCancelled else { return }
                let batch = self.dates
                let calendar = self.reloadCalendar
                self.dates.removeAll()
                self.reloadCalendar = false
                await perform(batch, calendar)
            } while generation == token && !Task.isCancelled && (!self.dates.isEmpty || self.reloadCalendar)
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        dates.removeAll()
        reloadCalendar = false
    }

    deinit { task?.cancel() }
}
