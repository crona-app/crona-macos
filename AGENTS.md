# Repository Guidelines

## Project Structure & Module Organization

`crona/` contains the macOS app source, split by responsibility: `App/` for app lifecycle, `Config/` for runtime discovery and protocol version, `Features/` for user-facing flows, `Platform/` for AppKit and windowing code, `Services/` for app services, `IPC/` for daemon communication, `Resources/` for bundled sounds, and `Shared/` for cross-cutting helpers. Tests live in `cronaTests/` and `cronaUITests/`. Release assets and packaging inputs live under `assets/release/` and `scripts/`. Project docs, release notes, and changelog entries live in `docs/`; parked feature plans live in `docs/plans/`.

`App/CompanionAppState.swift` is the composition root: it builds the services, routes daemon events, and exposes thin app and timer commands. Feature state belongs in a per-feature model under `Features/<Feature>/Models/` (for example `IssueCreatorModel`, `EndSessionModel`, `PopupCoordinator`), owned by `CompanionAppState` as a `private(set) lazy var` and wired with `[weak self]` closures. Do not add new `@Published` feature state to `CompanionAppState`.

## Build, Test, and Development Commands

- Build the macOS app locally: `xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug build`
- Run the full local test suite: `xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug test -destination "platform=macOS"`
- Run unit tests only (use this for most code changes): `xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug test -destination "platform=macOS" -only-testing:cronaTests`
- Verify patch hygiene before committing: `git diff --check`
- List files over the 500-line limit (see File Size & Responsibilities): `find crona cronaTests -name '*.swift' -exec wc -l {} + | awk '$1 > 500 && $2 != "total"' | sort -rn`

## Coding Style & Naming Conventions

Use Swift conventions already present in the repo: types in `UpperCamelCase`, functions and properties in `lowerCamelCase`, and descriptive enum cases. Match the surrounding file style rather than introducing new patterns. Keep edits scoped and prefer existing services/helpers over new abstractions. Use ASCII by default. Add comments only where the intent is not obvious from the code.

SwiftUI does not propagate changes from a nested `ObservableObject` to its parent. A view that reads a feature model or a service must hold that object as `@ObservedObject` (keep the view's existing init signature and assign the wrapper in `init`); reading it through `appState` alone will not refresh the view. `CompanionAppState` only forwards changes from preferences, core settings, the daemon connection, timer, context, and daily focus.

## File Size & Responsibilities

God objects and god files must not come back. Keep each type and file to one clear responsibility, and split by responsibility, not by technical layer.

- **500 lines is the limit.** A file over 500 lines has to earn that allowance: it must hold one cohesive concept that would be harder to follow if split (for example, a catalog of daemon wire models), and the pull request that takes it over the limit must say why. Size alone is never the justification.
- **Do not grow files that are already over the limit.** When a change touches one, extract the part being changed into its own type or file instead of adding to it. The existing oversized files are legacy debt, not precedent.
- **New feature state goes into a new model**, not an existing coordinator, service, or view.
- The same rules apply to test files: one test file per feature, no catch-all test class.

## Testing Guidelines

Tests use `XCTest`. Add or update focused tests in `cronaTests/` for behavior changes in services, feature models, popup positioning, daemon connectivity and transport, or release-channel logic. Follow the existing naming pattern: `test<BehaviorDescription>()`, for example `testInactivityPopupPositionerStagesCenteredPopupsOffscreen()`. Prefer narrow unit coverage over broad fixture-heavy tests unless a shared workflow changes.

- Put tests in the per-feature file they belong to (for example `DaemonClientTests.swift`, `TimerPresentationTests.swift`); add a new file for a new feature.
- Tests that drive app state subclass `DaemonTestCase` from `TestDaemonSupport.swift` and use its in-memory fake daemon (`issueCreatorConnection()`); extend that fake rather than writing a new one.
- Pass `isolatedPreferences()` when a test changes preferences, so tests never write the dev app's real defaults.
- Socket-level behavior is tested against a real Unix socket in `CronaUnixSocketTransportTests.swift`.
- Before moving or refactoring untested code, first add tests that pass against the current behavior.
- Unit tests cannot catch a view that stops refreshing; check UI flows by hand after changing what a view observes.

## Commit & Pull Request Guidelines

Recent history uses short, imperative commit subjects, for example `Switch DMG packaging to dmgbuild` and `Use virtualenv for dmgbuild in release workflow`. Keep commit messages specific to the user-visible or operational change. Name branches `<type>/<name>`, where type is `feat`, `fix`, `hotfix`, `refactor`, `docs`, or similar, for example `refactor/codebase-health`. For pull requests, include: a brief summary, testing performed, linked issue or release context, and screenshots when UI or DMG presentation changes.

## Release & Configuration Notes

The GitHub Actions release workflow in `.github/workflows/release.yml` builds, signs, notarizes, and publishes the app. DMG layout is configured in `scripts/dmgbuild_settings.py`. Version metadata lives in `crona.xcodeproj/project.pbxproj`; update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` deliberately when cutting releases.

## macOS Window Chrome Notes

- For the Settings window, prefer scene-level toolbar styling first. `Settings` needs an explicit `windowToolbarStyle(...)` on the scene to get the system toolbar surface to render correctly.
- If the toolbar background reads as fully transparent, apply `toolbarBackground(.regularMaterial, for: .windowToolbar)` and `toolbarBackgroundVisibility(.visible, for: .windowToolbar)` on the view tree, not on the `Scene`.
- `WindowService.registerSettingsWindow(_:)` should only adjust AppKit-level window behavior that the scene cannot express, such as `titlebarAppearsTransparent`, `backgroundColor`, `toolbarStyle`, and `titlebarSeparatorStyle`.
- Keep the toolbar split by OS version narrow and verify against screenshots before adding custom chrome. If the system toolbar still does not paint a real background, switch to a custom toolbar rather than stacking more translucent overlays.
