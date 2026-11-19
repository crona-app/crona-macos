import SwiftUI

struct GlanceHeader: View {
    @ObservedObject var state: CompanionAppState
    @ObservedObject var model: GlanceModel
    @ObservedObject private var day: PopoverDayModel

    init(state: CompanionAppState, model: GlanceModel) {
        self.state = state
        self.model = model
        day = model.day
    }

    var body: some View {
        HStack(spacing: 18) {
            Text("Glance").font(.title2.weight(.semibold)).foregroundStyle(PopupVisualTheme.primaryText)
            Spacer(minLength: 12)
            PopoverDayHeader(appState: state, day: model.day).frame(maxWidth: 280)
            Spacer(minLength: 12)
            Button { state.issueCreator.presentCreator() } label: {
                Label("Create Issue", systemImage: "plus")
            }.buttonStyle(GlanceButtonStyle()).disabled(!day.isToday || state.hasActiveFocusSession)
            Button { model.toggleCapture() } label: {
                Label("Capture", systemImage: "text.badge.plus")
            }.buttonStyle(GlanceButtonStyle()).disabled(!day.isToday || state.hasActiveFocusSession)
            Button { model.showsCustomization = true } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(GlanceButtonStyle()).help("Customize Glance")
            Button { model.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32).background(glassCapsuleBackground(emphasis: 0.08))
            }.buttonStyle(GlassPressButtonStyle()).help("Close Glance").accessibilityLabel("Close Glance")
        }.frame(minHeight: 40)
    }
}
