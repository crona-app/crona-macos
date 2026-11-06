import Foundation

/// Where Crona lives on GitHub. The owner is written once here for the app's links;
/// the release workflow takes it from the repository it runs in.
enum CronaProject {
    /// Owns the core `crona` repository, the source of truth for docs, support and feedback.
    static let repoOwner = "webxsid"
    static let coreRepoName = "crona"

    static var coreRepoSlug: String { "\(repoOwner)/\(coreRepoName)" }
    static var coreRepoURL: String { "https://github.com/\(coreRepoSlug)" }
    static var docsURL: String { "\(coreRepoURL)/tree/main/docs" }
    /// Support, bugs, feedback and ideas all go to the core repository's Discussions, as in the TUI.
    static var discussionsURL: String { "\(coreRepoURL)/discussions" }
}
