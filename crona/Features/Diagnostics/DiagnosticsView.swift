import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var diagnosticsService: DiagnosticsService

    init(appState: CompanionAppState) {
        self.appState = appState
        self.diagnosticsService = appState.diagnosticsService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                LabeledContent("Connection State") {
                    Text(diagnosticsService.snapshot.connectionState)
                }
                LabeledContent("Protocol Version") {
                    Text(diagnosticsService.snapshot.protocolVersion)
                }
                LabeledContent("Kernel Version") {
                    Text(diagnosticsService.snapshot.kernelVersion)
                }
                LabeledContent("Runtime Directory") {
                    Text(diagnosticsService.snapshot.runtimeDirectory)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Health") {
                    Text(diagnosticsService.snapshot.healthSummary)
                }
                LabeledContent("Last Reconnect") {
                    Text(diagnosticsService.snapshot.lastReconnect)
                }
            }

            HStack {
                Button("Copy Diagnostics") {
                    diagnosticsService.copyToPasteboard()
                }
                Button("Manual Reconnect") {
                    appState.manualReconnect()
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            Task { await diagnosticsService.refresh() }
        }
    }
}
