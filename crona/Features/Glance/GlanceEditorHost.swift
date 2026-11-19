import SwiftUI

/// Reuses the shared feature drafts while Glance owns their presentation.
struct GlanceEditorHost: View {
    @ObservedObject var state: CompanionAppState
    @ObservedObject var creator: IssueCreatorModel
    @ObservedObject var actions: IssueActionEditorModel
    @ObservedObject var habit: HabitEditorModel
    @ObservedObject var tags: TagEditorModel
    @ObservedObject var sharedCapture: IssueCaptureModel
    @ObservedObject var end: EndSessionModel

    private var visible: Bool {
        sharedCapture.isPresented || creator.isPresented || actions.editor != nil || habit.isPresented || habit.actionEditor != nil
            || tags.isPresented || end.isSheetPresented || state.popoverDetailsRoute != nil
    }

    private var hasForm: Bool {
        sharedCapture.isPresented || creator.isPresented || actions.editor != nil || habit.isPresented
            || habit.actionEditor != nil || tags.isPresented || end.isSheetPresented
    }

    var body: some View {
        if visible {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    Group {
                    if !hasForm, let route = state.popoverDetailsRoute {
                        PopoverDetailView(appState: state, route: route, habits: state.glance.habits,
                            issues: state.glance.issues, day: state.glance.day).padding(20)
                    } else {
                    ScrollView {
                        Group {
                            if end.isSheetPresented {
                                EndSessionSheetView(appState: state, endSession: end)
                            } else if actions.editor != nil {
                                IssueActionEditorView(appState: state, issueActions: actions).padding(24)
                            } else if case .delete(let item) = habit.actionEditor {
                                HabitDeleteConfirmationView(appState: state, habitEditor: habit, habit: item)
                            } else if tags.isPresented {
                                TagEditorView(appState: state, tagEditor: tags)
                            } else if creator.isPresented {
                                IssueCreatorView(appState: state, issueCreator: creator)
                            } else if sharedCapture.isPresented {
                                IssueCaptureView(appState: state, issueCapture: sharedCapture)
                            } else if habit.isPresented {
                                HabitCreatorView(appState: state, habitEditor: habit)
                            } else if let route = state.popoverDetailsRoute {
                                PopoverDetailView(appState: state, route: route, habits: state.glance.habits, issues: state.glance.issues, day: state.glance.day).padding(20)
                            }
                        }.frame(width: min(460, geometry.size.width - 32))
                    }
                    }
                    }
                    .frame(width: min(480, geometry.size.width - 16), height: min(760, geometry.size.height - 40))
                    .background(SheetGlassBackground())
                }
            }
        }
    }
}
