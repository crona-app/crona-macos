import SwiftUI

/// Measures unconstrained content at a stable width, then scrolls only above the height cap.
struct ContentSizedScrollView<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: FittingContentHeight.self, value: proxy.size.height)
                })
        }
        .frame(height: min(maximumHeight, contentHeight ?? maximumHeight))
        .clipped()
        .onPreferenceChange(FittingContentHeight.self) { height in
            guard height.isFinite, height > 0, abs((contentHeight ?? 0) - height) > 0.5 else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { contentHeight = height }
        }
    }
}

private struct FittingContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
