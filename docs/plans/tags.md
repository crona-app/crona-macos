# Spec: tags in the macOS app

Status: **approved surface, awaiting implementation plan**. Core reference: `crona` commits `43ef99a` through `e86971c` (since `v1.10.0-beta.2`).

## Goal

Show tags on issues and habits, filter by them the same way the TUI does, tag items from the menu bar, and see focus time per tag.

## Scope: glance + quick actions

## What the user sees

| Surface | Behavior |
|---|---|
| Issues and Habits rows | Up to 2 tag chips in each tag's color, then `+N`. |
| Issue and habit details | All tags. |
| Filter | A tag filter menu at the top of the Issues and Habits tabs. Reads and writes the shared `tagFilters` core setting, so the TUI and the Mac app stay in sync. |
| Stats tab | `Focus by tag`: top 5 tags by focused time for today and this week, from distribution data grouped by `tag`. |

## Actions

- **Tag field in the issue creator** (`IssueCreatorView` / `IssueCreatorModel`): suggests existing tags from `tag.list`, accepts new ones. Tags are sent with the create, or applied right after create with `issue.tags.set` if `issue.create` does not accept tags. Confirm when planning.
- **Edit tags…** in the issue and habit action menus. Saves with `issue.tags.set` / `habit.tags.set`.

Out of scope: `tag.rename`, `tag.set_color`, `tag.delete`, `tag.remove_unused`; a tag management screen.

## Data

- Optional `tags: [String]` on the issue and habit models (default empty).
- New `CronaTag` model matching `crona/shared/types/tags.go` (name, color, system flag; confirm fields when planning).
- `CronaDaemonClient`: `listTags()`, `setIssueTags(issueID:tags:)`, `setHabitTags(habitID:tags:)`, and read/write of `tagFilters` through the existing core settings path.
- Stats: request the distribution grouped by `tag` (`DistributionGroupTag`).

## Ownership

- New `TagsModel` in `Features/MenuBar/Models/`, owned by `CompanionAppState` as a `private(set) lazy var`. It caches `tag.list`, refreshes on tag op events (`OpEntityTag`), and owns the filter selection.
- Tag field state lives in `IssueCreatorModel` / `HabitEditorModel`, reusing `TagsModel` for suggestions.
- Views that show chips or the filter hold `TagsModel` as `@ObservedObject`.
- `StatsTabView.swift` is already large; put the Focus-by-tag section in a new view file.

## Testing

New `cronaTests/TagsModelTests.swift` on `DaemonTestCase`; extend the fake daemon with tag methods and `tagFilters`.

- Tag list loads and refreshes on a tag event.
- Filter selection round-trips through `tagFilters`.
- Setting tags on an issue or habit calls the daemon with the right payload.
- Chip overflow (`+N`) formatting.
- Decoding with and without `tags`.
- Issue creator: tags are sent on create (in the existing issue creator tests).
- Manual: chips, filter and Stats section refresh.
