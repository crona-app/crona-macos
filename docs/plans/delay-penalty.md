# Spec: delay penalty in the macOS app

Status: **approved surface, awaiting implementation plan**. Core reference: `crona` commits `af62ec4`, `7b3d729`, `171cf24` (since `v1.10.0-beta.2`).

## Goal

Make it obvious from the menu bar which planned issues are at high risk of slipping, without reproducing the TUI's penalty breakdown.

## Scope: glance + quick actions

The penalty is information only. There is no penalty-specific action; acting on it means working the issue or carrying it (see `carry-over.md`).

## What the user sees

| Surface | Behavior |
|---|---|
| Issues tab row | A small red risk marker on a planned issue whose plan entry has `penalty.highRisk == true`. No marker otherwise. |
| Issue details | One line: `High risk · delayed N days` (N = `currentDelayedDays`). If `penalty.ifPostponedOneDay.becomesHighRisk` is true and the issue is not already high risk, a second line: `Postponing 1 day makes this high risk`. |
| Stats / daily focus | A `High risk` count for today next to the existing planned/done counts. Hidden when zero. |

Out of scope: editing `planHighRiskThresholdTenths`, showing delay/frequency/stall components, accountability or backlog-pressure shares.

## Data

Extend `CronaDailyPlanEntry` (`crona/IPC/CronaDaemonModels.swift`) with optional fields so older daemons still decode:

- `penalty: CronaDailyPlanEntryPenalty?` with `highRisk: Bool`, `highRiskThreshold: Double`, `ifPostponedOneDay: CronaDailyPlanPenaltyProjection?` (`becomesHighRisk: Bool`). Other wire fields are ignored.

No new daemon methods. The data arrives through the existing `daily_plan.get` call in `DailyFocusService`.

## Ownership

- `DailyFocusService` already owns the daily plan; add a derived lookup `highRiskIssueIDs: Set<Int64>` and `highRiskCount`.
- Row and details views read it through an `@ObservedObject` reference to the service (see AGENTS.md on nested `ObservableObject`s).
- Shared presentation (marker color, detail text) goes in a new `crona/Shared/CronaPenaltyPresentation.swift`, next to `CronaIssueStatusPresentation.swift`.

## Testing

- Decoding: a plan entry with and without `penalty` decodes; unknown penalty fields are ignored.
- `DailyFocusService`: `highRiskIssueIDs` and `highRiskCount` reflect the plan.
- Presentation: detail text for high-risk, becomes-high-risk-if-postponed, and neither.
- Manual: row marker and Stats count refresh after the plan changes (unit tests cannot catch a view that stops refreshing).
