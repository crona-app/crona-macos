import AppKit
import SwiftUI

@MainActor
protocol GlanceWindowPresenting: AnyObject {
    var isVisible: Bool { get }
    func show(appState: CompanionAppState, model: GlanceModel) -> Bool
    func dismiss(restoreFocus: Bool)
}

@MainActor
final class GlanceWindowController: GlanceWindowPresenting {
    private var panel: GlancePanel?
    var isVisible: Bool { panel?.isVisible == true }
    private var previousApp: NSRunningApplication?
    private var displayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?
    private var monitor: Any?
    private var hostingView: NSHostingView<AnyView>?

    func show(appState: CompanionAppState, model: GlanceModel) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return false }
        previousApp = NSWorkspace.shared.frontmostApplication
        displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let panel = GlancePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Glance"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: Self.rootView(appState: appState, model: model, screen: screen))
        host.autoresizingMask = [.width, .height]
        hostingView = host
        panel.contentView = Self.backdrop(hosting: host, frame: screen.frame)
        self.panel = panel
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self, weak model] _ in
            Task { @MainActor in
                guard let self, let model else { return }
                guard let screen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == self.displayID
                }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
                self.displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                self.panel?.setFrame(screen.frame, display: true)
                // Swap the root view in place so transient @State survives.
                self.hostingView?.rootView = Self.rootView(appState: appState, model: model, screen: screen)
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model, weak panel] event in
            guard event.keyCode == 53, event.window === panel else { return event }
            // The capture editor handles its own Escape (autocomplete first, then closing the card).
            if panel?.firstResponder is NSTextView, model?.showsCapture == true { return event }
            Task { @MainActor in model?.handleEscape() }
            return nil
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Blurs whatever is behind the panel across the whole display, independent of the content insets.
    private static func backdrop(hosting host: NSView, frame: NSRect) -> NSView {
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        let tint = NSView(frame: blur.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        tint.autoresizingMask = [.width, .height]
        host.frame = blur.bounds
        blur.addSubview(tint)
        blur.addSubview(host)
        return blur
    }

    private static func rootView(appState: CompanionAppState, model: GlanceModel, screen: NSScreen) -> AnyView {
        AnyView(GlanceView(appState: appState, model: model)
            .padding(contentInsets(frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top)))
    }

    static func contentInsets(frame: NSRect, visibleFrame: NSRect, safeTop: CGFloat) -> EdgeInsets {
        EdgeInsets(top: max(safeTop, frame.maxY - visibleFrame.maxY, 24),
                   leading: max(0, visibleFrame.minX - frame.minX),
                   bottom: max(0, visibleFrame.minY - frame.minY),
                   trailing: max(0, frame.maxX - visibleFrame.maxX))
    }

    func dismiss(restoreFocus: Bool) {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if restoreFocus { previousApp?.activate() }
        previousApp = nil
    }

    isolated deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

private final class GlancePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
