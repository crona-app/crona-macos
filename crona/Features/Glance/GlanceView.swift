import SwiftUI

struct GlanceView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var model: GlanceModel
    @ObservedObject var day: PopoverDayModel
    @ObservedObject private var coreSettings: CoreSettingsService

    init(appState: CompanionAppState, model: GlanceModel) {
        self.appState = appState
        self.model = model
        day = model.day
        coreSettings = appState.coreSettingsService
    }

    private var showsCard: Bool {
        !appState.hasActiveFocusSession && day.isToday && !model.isSelectedDayAway
            && (model.showsCapture || model.showsSetup)
    }

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
            if !model.isSelectedDayAway || appState.hasActiveFocusSession {
                GlanceEditorHost(state: appState, creator: appState.issueCreator, actions: appState.issueActions,
                    habit: appState.habitEditor, tags: appState.tagEditor, sharedCapture: appState.issueCapture, end: appState.endSession)
            }
        }.companionAppearance(appState)
    }

    private var content: some View {
        VStack(spacing: 16) {
            GlanceHeader(state: appState, model: model)
            if !appState.hasActiveFocusSession && day.isToday && !model.isSelectedDayAway {
                HStack {
                    Text("Ready to focus").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await model.setAwayMode(true) }
                    } label: {
                        Label("Mark Today as Away", systemImage: "figure.walk")
                    }
                    .buttonStyle(GlanceButtonStyle())
                    .disabled(!model.canChangeAwayMode || coreSettings.isSaving)
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
            if model.isSelectedDayAway && !appState.hasActiveFocusSession {
                GlanceAwayView(settings: coreSettings, isToday: day.isToday,
                    canChangeMode: model.canChangeAwayMode, onDisable: {
                        Task { await model.setAwayMode(false) }
                    })
            } else {
                if day.isToday, let error = coreSettings.lastErrorDescription {
                    Text(error).font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
                }
                GlanceDayPanes(state: appState, model: model, day: day,
                    issues: model.issues, habits: model.habits, stats: model.stats)
            }
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
