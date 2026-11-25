import SwiftUI

struct GlancePointerPopover<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var popoverContent: () -> PopoverContent
    @State private var size: CGSize = .zero
    @State private var pointerAnchor: UnitPoint?
    @State private var isPointerOverRow = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isPointerOverRow = true
                    guard !isPresented, size.width > 0, size.height > 0 else { return }
                    pointerAnchor = UnitPoint(
                        x: min(1, max(0, location.x / size.width)),
                        y: min(1, max(0, location.y / size.height))
                    )
                case .ended:
                    isPointerOverRow = false
                    if !isPresented { pointerAnchor = nil }
                }
            }
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .point(pointerAnchor ?? .trailing),
                arrowEdge: pointerAnchor == nil ? .trailing : .bottom,
                content: popoverContent
            )
            .onChange(of: isPresented) { _, presented in
                if !presented && !isPointerOverRow { pointerAnchor = nil }
            }
    }
}
