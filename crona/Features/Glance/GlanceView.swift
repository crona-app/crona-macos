import SwiftUI

struct GlanceView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var model: GlanceModel
    @ObservedObject var day: PopoverDayModel

    init(appState: CompanionAppState, model: GlanceModel) {
        self.appState = appState
        self.model = model
        day = model.day
    }

    private var showsCard: Bool { day.isToday && (model.showsCapture || model.showsSetup) }

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).ignoresSafeArea()
            content
            if showsCard {
                Color.black.opacity(0.28).ignoresSafeArea()
                card.transition(.opacity)
            }
            if model.showsCustomization {
                Color.black.opacity(0.28).ignoresSafeArea()
                VStack {
                    ScrollView { GlanceCustomizationView(preferences: appState.preferences).padding(24) }
                    Button("Done") { model.showsCustomization = false }.padding()
                }.frame(width: 560).frame(maxHeight: 650).background(SheetGlassBackground())
            }
            GlanceEditorHost(state: appState, creator: appState.issueCreator, actions: appState.issueActions,
                habit: appState.habitEditor, tags: appState.tagEditor, sharedCapture: appState.issueCapture, end: appState.endSession)
        }.companionAppearance(appState)
    }

    private var content: some View {
        VStack(spacing: 16) {
            GlanceHeader(state: appState, model: model)
            if appState.hasActiveFocusSession {
                GlanceLiveSessionStrip(state: appState, model: model, timer: appState.timerService)
            } else if day.isToday {
                HStack {
                    Text("Ready to focus").foregroundStyle(.secondary)
                    Spacer()
                    Button { model.prepare() } label: { Label("Quick Session", systemImage: "timer") }
                        .buttonStyle(GlanceButtonStyle())
                }
            }
            if appState.daemonConnection.connectionState != .connected {
                HStack {
                    Label("Disconnected · showing cached day data", systemImage: "wifi.slash")
                    Button("Reconnect", action: appState.manualReconnect).buttonStyle(GlanceButtonStyle())
                }
            }
            if day.isRecordedAway(in: appState.coreSettingsService.settings) {
                Label("Recorded away day", systemImage: "figure.walk")
            }
            GlanceDayPanes(state: appState, model: model, day: day, issues: model.issues, habits: model.habits, stats: model.stats)
        }.padding(24).frame(maxWidth: 1800).frame(maxWidth: .infinity)
    }

    @ViewBuilder private var card: some View {
        Group {
            if model.showsSetup {
                GlanceSessionWidget(state: appState, model: model, setup: model.setup)
            } else {
                IssueCaptureView(appState: appState, issueCapture: model.capture, width: 460,
                    onImport: { await model.importCapture() }, onClose: { model.showsCapture = false })
            }
        }.environment(\.dialogSurfaceProvided, true)
        .background(SheetGlassBackground())
    }
}
