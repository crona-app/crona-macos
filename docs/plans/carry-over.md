# Spec: carry-over in the macOS app

Status: **approved surface, awaiting implementation plan**. Core reference: `crona` commits `d7477bb`, `841389e`, `3157110`, `cbccd89`, `3ac3ed9` (since `v1.10.0-beta.2`).

## Goal

Show which issues were carried to today, flag ones that keep getting carried, and let the user carry an unfinished issue to tomorrow from the menu bar.

## Scope: glance + quick actions

## What the user sees

| Surface | Behavior |
|---|---|
| Issues tab row | Lavender `Carried ×N` badge when `carryCount > 0`. When `stalled == true`, the badge reads `Stalled` in the red risk color instead. |
| Issue details | `Carried from <date>` from `carriedFromDate`, formatted like other dates in the popover. |
| Past day, Planned section | Issues the day carried to a later day still appear, with a lavender `Carried` chip in place of their status (matches the TUI). Reached through the shared day picker. |
| Auto carry | No notification. The day-boundary carry is silent; the badge is the signal. |

The issue keeps its real status. `IssueStatus "carried"` is display-only in the core and is never sent on an issue, so `CronaIssueStatus` does not gain a case.

## Actions

- **Carry to Tomorrow**: in the row menu of every non-carried row in today's Planned and Overdue sections. Calls `issue.carry` without a date, so the core picks the next working day.
- **Undo Carry**: a toast for 5 seconds after a manual carry (above the Start Ad Hoc footer), and an `Undo Carry` item in the row menu of a carried row on a past day. Calls `issue.carry.undo`; if the core's rollback window has passed, its error shows in the toast area.
- On failure, show the daemon error in the existing popover error style and leave the plan untouched.

Out of scope: `carryOverEnabled`, `carryOverMinMinutes`, `carryOverStallAfter` settings; carry history views.

## Data

- `CronaDailyPlanEntry` gains optional `carriedFromDate`, `carryCount` and `stalled`; other carry wire fields are ignored. Missing fields decode to nil.
- `CronaDaemonClient`: `carryIssue(issueID:)` (`{ "id" }`) and `undoCarry(issueID:)` (`CronaNumericIDRequest`).

## Ownership

- `CarryOverModel` in `Features/MenuBar/Models/`, owned by `CompanionAppState` as `private(set) lazy var carryOver`. It owns in-flight, undo offer and error state, and its `onChanged` closure refreshes `DailyIssuesModel` and `DailyFocusService` after a success.
- `DailyIssueSections.build` turns plan entries into `DailyFocusIssue.carry` (`DailyFocusCarry`) and `carriedAway`.
- Copy, icons and the lavender `.carried` semantic color live in `crona/Shared/CronaCarryPresentation.swift` and `PopupVisualTheme`; the toast is `Components/CarryUndoToast.swift`.

## Testing

`cronaTests/CarryOverTests.swift` (model, copy, color) and `DailyIssueSectionsTests.swift` (decoding, carried-away rows), subclassing `DaemonTestCase`; extend the fake daemon with `issue.carry` / `issue.carry.undo`.

- Carry calls the daemon and refreshes the plan; undo reverses it.
- Undo toast expires.
- Daemon error surfaces and leaves state unchanged.
- Decoding of carry fields, with and without them present.
- Manual: badge appears and clears after carry and undo.
