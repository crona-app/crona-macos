import AppKit
import SwiftUI

/// The status menu needs an imperative opener; content and navigation stay in SwiftUI.
@MainActor
final class LibraryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let windowService: WindowService
    private let onClosed: () -> Void
    private var isPresented = false

    init(windowService: WindowService, onClosed: @escaping () -> Void) {
        self.windowService = windowService
        self.onClosed = onClosed
    }

    func show(appState: CompanionAppState) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.title = "Crona Library"
            window.minSize = NSSize(width: 800, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: LibraryRootView(appState: appState))
            window.setContentSize(NSSize(width: 1000, height: 720))
            window.center()
            window.setFrameAutosaveName("CronaLibrary")
            self.window = window
        }
        if !isPresented {
            isPresented = true
            windowService.beginExternalWindowPresentation()
        }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard isPresented else { return }
        isPresented = false
        onClosed()
        windowService.endExternalWindowPresentation()
    }
}
