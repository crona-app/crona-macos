import Combine
import Foundation

@MainActor
final class GlobalShortcutsModel: ObservableObject {
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var bindings: [String: SettingsShortcut] = [:]
    @Published private(set) var creatorFocusGeneration = 0
    var isRecording = false { didSet { held.removeAll() } }
    private let preferences: PreferencesService
    private let registry: ShortcutRegistering
    private let perform: (GlobalShortcutAction) async -> Void
    private var active: [GlobalShortcutAction: UInt32] = [:]
    private var registered: [GlobalShortcutAction: SettingsShortcut] = [:]
    private var nextID: UInt32 = 0
    private var held: Set<UInt32> = []
    private var executing: Set<GlobalShortcutAction> = []

    init(preferences: PreferencesService, registry: ShortcutRegistering,
         perform: @escaping (GlobalShortcutAction) async -> Void) {
        self.preferences = preferences
        self.registry = registry
        self.perform = perform
        registry.onEvent = { [weak self] id, released in self?.receive(id: id, released: released) }
    }

    func focusCreator() { creatorFocusGeneration &+= 1 }

    func reload() {
        bindings = preferences.preferences.globalShortcuts
        for action in GlobalShortcutAction.allCases {
            let binding = bindings[action.rawValue]
            guard registered[action] != binding else { continue }
            do { try replace(binding, for: action); errors[action.rawValue] = nil }
            catch { errors[action.rawValue] = error.localizedDescription }
        }
    }

    @discardableResult
    func assign(_ binding: SettingsShortcut?, to action: GlobalShortcutAction) -> Bool {
        if let binding {
            guard binding.modifiers & UInt32(0x1900) != 0 else {
                errors[action.rawValue] = "Include Command, Control, or Option."
                return false
            }
            if let other = GlobalShortcutAction.allCases.first(where: {
                guard $0 != action, let candidate = bindings[$0.rawValue] else { return false }
                return candidate.keyCode == binding.keyCode && candidate.modifiers == binding.modifiers
            }) {
                errors[action.rawValue] = "Already assigned to \(other.title)."
                return false
            }
        }
        do {
            if registered[action] != binding { try replace(binding, for: action) }
            bindings[action.rawValue] = binding
            preferences.preferences.globalShortcuts = bindings
            errors[action.rawValue] = nil
            return true
        } catch {
            errors[action.rawValue] = error.localizedDescription
            return false
        }
    }

    private func replace(_ binding: SettingsShortcut?, for action: GlobalShortcutAction) throws {
        var newID: UInt32?
        if let binding {
            nextID &+= 1
            try registry.register(binding, id: nextID)
            newID = nextID
        }
        if let oldID = active[action] { registry.unregister(id: oldID) }
        active[action] = newID
        registered[action] = binding
        held.removeAll()
    }

    private func receive(id: UInt32, released: Bool) {
        if released { held.remove(id); return }
        guard !isRecording, held.insert(id).inserted,
              let action = active.first(where: { $0.value == id })?.key,
              !executing.contains(action) else { return }
        executing.insert(action)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await perform(action)
            executing.remove(action)
        }
    }

    func stop() {
        for id in active.values { registry.unregister(id: id) }
        active.removeAll()
        registered.removeAll()
        held.removeAll()
    }
}
