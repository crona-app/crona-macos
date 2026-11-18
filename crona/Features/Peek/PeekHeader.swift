import SwiftUI

struct PeekHeader: View {
    @ObservedObject var state: CompanionAppState
    @ObservedObject var model: PeekModel
    @ObservedObject private var day: PopoverDayModel

    init(state: CompanionAppState, model: PeekModel) {
        self.state = state
        self.model = model
        day = model.day
    }

    var body: some View {
        HStack(spacing: 18) {
            Text("Peek").font(.title2.weight(.semibold)).foregroundStyle(PopupVisualTheme.primaryText)
            Spacer(minLength: 12)
            PopoverDayHeader(appState: state, day: model.day).frame(maxWidth: 280)
            Spacer(minLength: 12)
            Button { model.toggleCapture() } label: {
                Label("Capture", systemImage: "text.badge.plus")
            }.buttonStyle(PeekButtonStyle()).disabled(!day.isToday)
            Button { model.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32).background(glassCapsuleBackground(emphasis: 0.08))
            }.buttonStyle(GlassPressButtonStyle()).help("Close Peek").accessibilityLabel("Close Peek")
        }.frame(minHeight: 40)
    }
}
