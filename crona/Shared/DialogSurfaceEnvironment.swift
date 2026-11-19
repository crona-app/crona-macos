import SwiftUI

private struct DialogSurfaceProvidedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dialogSurfaceProvided: Bool {
        get { self[DialogSurfaceProvidedKey.self] }
        set { self[DialogSurfaceProvidedKey.self] = newValue }
    }
}
