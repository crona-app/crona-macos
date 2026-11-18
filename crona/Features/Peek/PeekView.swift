import SwiftUI

struct PeekView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var model: PeekModel
    @ObservedObject var day: PopoverDayModel

    init(appState: CompanionAppState, model: PeekModel) {
        self.appState = appState
        self.model = model
        day = model.day
    }

    private var showsCard: Bool { day.isToday && (model.showsCapture || model.showsSetup) }

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture { model.dismiss() }
            content
            if showsCard {
                Color.black.opacity(0.28).ignoresSafeArea().onTapGesture { model.handleEscape() }
                card.transition(.opacity)
            }
        }.companionAppearance(appState)
    }

    private var content: some View {
        VStack(spacing: 16) {
            PeekHeader(state: appState, model: model)
            if appState.hasActiveFocusSession {
                PeekLiveSessionStrip(state: appState, model: model, timer: appState.timerService)
            } else if day.isToday {
                HStack {
                    Text("Ready to focus").foregroundStyle(.secondary)
                    Spacer()
                    Button { model.prepare() } label: { Label("Quick Session", systemImage: "timer") }
                        .buttonStyle(PeekButtonStyle())
                }
            }
            if appState.daemonConnection.connectionState != .connected {
                HStack {
                    Label("Disconnected · showing cached day data", systemImage: "wifi.slash")
                    Button("Reconnect", action: appState.manualReconnect).buttonStyle(PeekButtonStyle())
                }
            }
            if day.isRecordedAway(in: appState.coreSettingsService.settings) {
                Label("Recorded away day", systemImage: "figure.walk")
            }
            PeekDayPanes(state: appState, model: model, day: day, issues: model.issues, habits: model.habits, stats: model.stats)
        }.padding(24).frame(maxWidth: 1800).frame(maxWidth: .infinity)
    }

    @ViewBuilder private var card: some View {
        Group {
            if model.showsSetup {
                PeekSessionWidget(state: appState, model: model, setup: model.setup)
            } else {
                IssueCaptureView(appState: appState, issueCapture: model.capture, width: 460,
                    onImport: { await model.importCapture() }, onClose: { model.showsCapture = false })
            }
        }.background(SheetGlassBackground())
    }
}
