import AppKit
import Carbon.HIToolbox
import Combine

struct SettingsShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        var prefix = ""
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey); prefix += "⌃" }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey); prefix += "⌥" }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey); prefix += "⇧" }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey); prefix += "⌘" }
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option),
              let character = event.charactersIgnoringModifiers?.uppercased(),
              !character.isEmpty
        else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = carbonModifiers
        display = prefix + character
    }
}

@MainActor
protocol ShortcutRegistering: AnyObject {
    var onEvent: ((UInt32, Bool) -> Void)? { get set }
    func register(_ binding: SettingsShortcut, id: UInt32) throws
    func unregister(id: UInt32)
}

@MainActor
final class SettingsShortcutService: ShortcutRegistering {
    var onEvent: ((UInt32, Bool) -> Void)?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, data in
            guard let event, let data else { return noErr }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                identifier.signature == OSType(0x43524F4E) else { return noErr }
            let service = Unmanaged<SettingsShortcutService>.fromOpaque(data).takeUnretainedValue()
            let id = identifier.id
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            Task { @MainActor [weak service] in service?.onEvent?(id, released) }
            return noErr
        }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ binding: SettingsShortcut, id: UInt32) throws {
        guard handler != nil else { throw RegistrationError() }
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(binding.keyCode, binding.modifiers,
            EventHotKeyID(signature: OSType(0x43524F4E), id: id), GetEventDispatcherTarget(), 0, &reference)
        guard result == noErr, let reference else { throw RegistrationError() }
        registrations[id] = reference
    }

    func unregister(id: UInt32) {
        if let reference = registrations.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
    }

    struct RegistrationError: LocalizedError {
        var errorDescription: String? { "This shortcut could not be registered. Choose another combination." }
    }

    isolated deinit {
        for reference in registrations.values { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
