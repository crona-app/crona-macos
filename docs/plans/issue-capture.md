# Spec: bulk issue capture and the Inbox in the macOS app

Status: **built on `feat/issue-capture`**. Core reference: `crona` commits `dfdbba6` through `d695e5d` (since `v1.10.0-beta.2`).

## Goal

Keep the system Inbox out of pickers, let the user triage Inbox issues, and capture several issues at once from the menu bar.

## Scope: glance + quick actions

## Step 0: compatibility fix (ship first)

The core now creates a system Inbox repo and stream (`system: true`). Hide every repo and stream with `system == true` from all repo and stream pickers (issue creator, ad hoc attribution, and any others), the same way the TUI does (`d695e5d`). This can ship on its own before the rest.

## What the user sees

| Surface | Behavior |
|---|---|
| Repo/stream pickers | System repos and streams are hidden. |
| Issues tab | A fourth `Inbox (N)` segment beside Planned/Overdue/Upcoming, shown only when the Inbox has issues. Each Inbox row's menu has a `Move to` submenu of repos and streams (system entries hidden) that calls `issue.move`. |
| Capture sheet | A small multi-line editor for `- ` lines. As the user types, a debounced `issue.capture.parse` fills an inline preview: title, tags, estimate, date, and the target repo/stream or `Inbox`. Rows the daemon flags show their flags in the error color and block import until the text is fixed. `Import N Issues` calls `issue.capture.import` and closes the sheet. |

## Actions

- Open capture from the `text.badge.plus` icon button beside `Start Ad Hoc` in the Issues tab footer (help: `Capture issues`). There is no global shortcut.
- Move an Inbox issue with `Move to`.
- Parse errors show inline under the editor. An import failure keeps the text so nothing is lost.

Out of scope: a global capture shortcut; per-row repo/stream choice before import (the user fixes the text and it re-parses); capture from notes.

## Data

- Optional `system: Bool` (default false) on `CronaRepo` and `CronaStream`.
- Capture DTOs matching `crona/shared/dto/capture.go`.
- `CronaDaemonClient`: `parseCapture(text:)`, `importCapture(...)`, `moveIssue(issueID:repoID:streamID:)`. Confirm param shapes against `docs/reference/socket-api.md` when planning.

## Ownership

- New feature folder `Features/IssueCapture/` with `Models/IssueCaptureModel.swift` and `Views/IssueCaptureView.swift`. `CompanionAppState` owns the model as a `private(set) lazy var`.
- `IssueCaptureModel` owns the editor text, debounce, parse preview, in-flight and error state.
- Inbox section and `Move to…` live with the Issues tab. Inbox state is derived from the issue list (issues whose stream is the system Inbox).
- A shared helper filters system repos and streams so every picker uses the same rule.

## Testing

- Picker filtering: system repos and streams are excluded (extend the existing issue creator tests).
- New `cronaTests/IssueCaptureTests.swift` on `DaemonTestCase`; extend the fake daemon with `issue.capture.parse`, `issue.capture.import`, `issue.move`.
  - Debounced parse fires once per pause in typing.
  - Import sends the parsed proposals and clears state on success.
  - Import failure keeps the text.
  - Move calls the daemon and the issue leaves the Inbox section.
- Decoding of `system` with and without the field.
- Manual: capture sheet from the footer button; Inbox segment appears and disappears.
