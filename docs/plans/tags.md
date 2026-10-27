# Spec: tags in the macOS app

Status: **built on `feat/tags`**. Core reference: `crona` commits `43ef99a` through `e86971c` (since `v1.10.0-beta.2`).

## Goal

Show tags on issues and habits, filter by them the same way the TUI does, tag items from the menu bar, and see focus time per tag.

## Scope: glance + quick actions

## What the user sees

| Surface | Behavior |
|---|---|
| Issues and Habits rows | Up to 3 overlapping color dots beside the title, then `+N`; hovering shows every tag as a chip. |
| Issue and habit details | All tags. |
| Filter | A tag filter icon menu (Show / Hide / Clear, including `Untagged`) beside the Issues section switch and at the left of the Habits day pill. It reads and writes the `issues` and `habits` entries of the shared `tagFilters` core setting (`+a -b` queries, the TUI's format) and reloads on `settings.changed`, so the TUI and the Mac app stay in sync. Tags in a saved filter that no longer exist are ignored. |
| Stats tab | `Focus by tag`: top 5 tags by focused time for the shown day or its week (Monday through that day), from distribution data grouped by `tag`. |

## Actions

- **Tag field in the issue and habit creators** (create only): suggests existing tags from `tag.list` and accepts new ones, normalized like the kernel. Tags are sent with `issue.create` / `habit.create`.
- **Edit Tags…** in the issue and habit menus opens a small sheet (`TagEditorModel` / `TagEditorView`). Saves with `issue.tags.set` / `habit.tags.set`.

Out of scope: `tag.rename`, `tag.set_color`, `tag.delete`, `tag.remove_unused`; a tag management screen.

## Data

- Optional `tags: [String]` on the issue and habit models (default empty).
- New `CronaTag` model matching `crona/shared/types/tags.go` (name, color, system flag; confirm fields when planning).
- `CronaDaemonClient`: `listTags()`, `setIssueTags(issueID:tags:)`, `setHabitTags(habitID:tags:)`, and read/write of `tagFilters` through the existing core settings path.
- Stats: request the distribution grouped by `tag` (`DistributionGroupTag`).

## Ownership

- New feature folder `Features/Tags/`. `TagsModel` is owned by `CompanionAppState` as `private(set) lazy var tags`; it caches `tag.list`, reloads on `tags.changed` and `settings.changed`, and owns the filter selection. `TagEditorModel` (`tagEditor`) and `TagFocusModel` (`tagFocus`) are owned the same way.
- Tag field state lives in `IssueCreatorModel` / `HabitEditorModel`, reusing `TagsModel` for suggestions.
- Views that show chips or the filter hold `TagsModel` as `@ObservedObject`.
- `StatsTabView.swift` is already large; the Focus-by-tag section is `Features/Tags/Views/FocusByTagSection.swift`.

## Testing

New `cronaTests/TagsTests.swift` on `DaemonTestCase`; extend the fake daemon with tag methods and `tagFilters`.

- Tag list loads and refreshes on a tag event.
- Filter selection round-trips through `tagFilters`.
- Setting tags on an issue or habit calls the daemon with the right payload.
- Chip overflow (`+N`) formatting.
- Decoding with and without `tags`.
- Issue creator: tags are sent on create (in the existing issue creator tests).
- Manual: chips, filter and Stats section refresh.
