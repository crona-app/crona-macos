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
| Auto carry | No notification. The day-boundary carry is silent; the badge is the signal. |

The issue keeps its real status. `IssueStatus "carried"` is display-only in the core and is never sent on an issue, so `CronaIssueStatus` does not gain a case.

## Actions

- **Carry to tomorrow**: in the issue actions menu for a planned issue that is overdue or not done today. Calls `issue.carry`.
- **Undo carry**: a toast for about 5 seconds after a manual carry, and an `Undo carry` item in details for an issue carried today. Calls `issue.carry.undo`.
- On failure, show the daemon error in the existing popover error style and leave the plan untouched.

Out of scope: `carryOverEnabled`, `carryOverMinMinutes`, `carryOverStallAfter` settings; carry history views.

## Data

- Extend `CronaDailyPlanEntry` with optional `carriedFromEntryID`, `carriedToEntryID`, `carriedFromDate`, `carriedToDate`, `carryCount` (default 0), `stalled` (default false), `workedSeconds` (default 0). Decode missing fields to defaults.
- `CronaDaemonClient`: `carryIssue(issueID:)` and `undoCarry(issueID:)`. Confirm exact param shapes against `crona/shared/dto/requests.go` and `docs/reference/socket-api.md` when planning.

## Ownership

- New `CarryOverModel` in `Features/MenuBar/Models/`, owned by `CompanionAppState` as a `private(set) lazy var`, wired with `[weak self]` closures. It owns the action state (in-flight, undo toast, error) and asks `DailyFocusService` to refresh after success.
- Badge display reads plan entries from `DailyFocusService`.
- Badge color goes in the shared presentation helpers.

## Testing

New `cronaTests/CarryOverModelTests.swift`, subclassing `DaemonTestCase`; extend the fake daemon with `issue.carry` / `issue.carry.undo`.

- Carry calls the daemon and refreshes the plan; undo reverses it.
- Undo toast expires.
- Daemon error surfaces and leaves state unchanged.
- Decoding of carry fields, with and without them present.
- Manual: badge appears and clears after carry and undo.
