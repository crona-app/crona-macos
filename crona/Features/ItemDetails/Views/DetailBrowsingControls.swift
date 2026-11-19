import AppKit
import SwiftUI

struct DetailBrowsingControls: View {
    let appState: CompanionAppState
    @ObservedObject private var browser: DetailBrowserModel
    @ObservedObject private var issues: DailyIssuesModel
    @ObservedObject private var habits: HabitsService
    @ObservedObject private var tags: TagsModel

    init(appState: CompanionAppState) {
        self.appState = appState
        browser = appState.detailBrowser
        issues = appState.glance.isPresented ? appState.glance.issues : appState.dailyIssues
        habits = appState.glance.isPresented ? appState.glance.habits : appState.habitsService
        tags = appState.tags
    }
    var body: some View {
        let filtered = habits.snapshot.filtered(by: tags.filter(for: .habits), known: tags.knownNames).items
        let ids = browser.ids(issues: issues.sections, habits: filtered)
        HStack {
            Button {
                browse(-1, ids: ids)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(browser.neighbor(-1, ids: ids) == nil)
            Spacer()
            Button {
                browse(1, ids: ids)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(browser.neighbor(1, ids: ids) == nil)
        }
        .font(.caption).buttonStyle(.borderless).padding(.horizontal, 8)
        .background(DetailArrowKeys { offset in browse(offset, ids: ids) })
    }
    private func browse(_ offset: Int, ids: [Int64]) {
        guard let id = browser.neighbor(offset, ids: ids) else { return }
        browser.select(id)
        appState.popoverDetailsRoute =
            browser.source == .habits ? .habitDetails(habitID: id) : .issueDetails(issueID: id)
    }
}

/// A local monitor lets scrolling keep focus while leaving text editor arrows alone.
private struct DetailArrowKeys: NSViewRepresentable {
    let browse: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.install(view: view, browse: browse) }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }

    @MainActor final class Coordinator {
        private var monitor: Any?
        func install(view: NSView, browse: @escaping (Int) -> Void) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view] event in
                guard let window = view?.window, event.window === window,
                    !(window.firstResponder is NSTextView),
                    event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                    event.keyCode == 123 || event.keyCode == 124
                else { return event }
                browse(event.keyCode == 123 ? -1 : 1)
                return nil
            }
        }
        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
