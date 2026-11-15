import Combine
import Foundation

/// Invalidates loaded feature data on daemon changes, including reconnection.
@MainActor
final class FeatureRefreshObserver {
    private var subscriptions = Set<AnyCancellable>()

    init(connection: DaemonConnectionService, events: Set<String>, invalidate: @escaping () -> Void) {
        NotificationCenter.default.publisher(for: .cronaDaemonEventReceived)
            .compactMap { $0.object as? CronaProtocolEvent }
            .filter { events.contains($0.type) }
            .sink { _ in invalidate() }.store(in: &subscriptions)
        connection.$connectionState.removeDuplicates().dropFirst()
            .sink { _ in invalidate() }.store(in: &subscriptions)
        connection.$currentDate.removeDuplicates().dropFirst()
            .sink { _ in invalidate() }.store(in: &subscriptions)
    }
}
