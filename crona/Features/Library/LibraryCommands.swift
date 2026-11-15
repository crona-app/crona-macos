import Foundation

extension CompanionAppState {
    func openLibrary(_ destination: LibraryDestination? = nil) {
        if let destination { libraryNavigation.destination = destination }
        if destination == .review { review.anchor = day.selectedDate }
        statusBarService.dismissPopup()
        libraryWindow.show(appState: self)
        checkInHistory.setVisible(libraryNavigation.destination == .checkIns)
        review.setVisible(libraryNavigation.destination == .review)
    }

    func openActivityIssueDetails(_ issue: DailyFocusIssue) {
        detailBrowser.open(issue: issue, section: nil)
        popoverDetailsRoute = .issueDetails(issueID: issue.id)
    }
}
