# Future plan: macOS widget

Status: **parked**. These are brainstorming results, not an approved spec. Before building, turn this into a spec and an implementation plan, starting with the signing spike below.

## Goal

A desktop and Notification Center widget that shows what Crona is doing without opening the menu bar popover.

## Decisions so far

| Topic | Decision |
|---|---|
| Purpose | A mix: the running session when there is one, today's progress when idle |
| Interactivity | **Display only** in v1. Clicking opens Crona. Buttons (pause, resume, end, start) are a later version |
| Sizes | One widget kind, in **Small** and **Medium** |
| App not running or daemon unreachable | Show a clear **"Crona isn't running" / "Not connected"** state, never numbers that may be stale |

### Content

```
SMALL (session)        SMALL (idle)
+-------------+        +-------------+
|  (ring)     |        | Today       |
|  18:42      |        | 2h 15m      |
| Fix sync bug|        | Score 82    |
+-------------+        +-------------+

MEDIUM (idle)
+------------------------------+
| Today 2h 15m  Score 82       |
| Next up                      |
|  - Fix sync bug      25m est |
|  - Write release notes       |
|  - Review PR #41             |
+------------------------------+
```

- **Small:** during a session, the issue, a live timer and a progress ring. When idle, today's focus time and focus score.
- **Medium:** during a session, the same plus today's totals. When idle, today's totals and the next 3 planned issues.
- The timer counts with `Text(_:style: .timer)` and `ProgressView(timerInterval:)`, so it ticks without per-second timeline reloads. A paused session shows a fixed time.
- "Today" means the daemon's logical date, as the popover already does.

### Success criteria

- After any change, the widget agrees with the popover within a few seconds.
- The widget never shows a session as running after the app has quit or crashed. A crash is reflected within the snapshot expiry window (below).

## Constraints

- **Distribution is Developer ID, not the App Store, and must stay that way.** The app relies on a daemon outside any sandbox, so the main app stays unsandboxed (`ENABLE_APP_SANDBOX = NO`).
- **The widget extension must be sandboxed.** macOS won't load an unsandboxed WidgetKit extension, whatever the distribution. So data must cross from the unsandboxed app into the sandboxed widget.
- **App Group ID must be team-prefixed.** Release signing is manual Developer ID with no provisioning profile (`Config/ExportOptions.plist`). Use `8QB9GBLWP5.com.webxsid.crona`, not `group.com.webxsid.crona`. Without a profile, the `group.` form may prompt the user or fail on recent macOS.
- **Separate dev and release groups.** The dev build (`com.webxsid.crona.dev`) uses `8QB9GBLWP5.com.webxsid.crona.dev`, so a dev build never overwrites the installed app's widget data. The widget bundle IDs follow: `com.webxsid.crona.widget` and `com.webxsid.crona.dev.widget`.
- **Deployment target is macOS 14.** That is enough for the timer styles above, and for interactive widgets later.
- **Release pipeline:** `xcodebuild archive` plus `-exportArchive` with `method = developer-id` signs embedded extensions. Notarization submits the whole app, and the existing `codesign --verify --deep` check covers the appex. Confirm this in the spike rather than assuming it.

## Recommended approach: the app writes a snapshot to the App Group container

1. The app builds a small `Codable` widget snapshot from state it already holds: connection state, the timer snapshot, the active issue, today's metrics and focus score, and the next planned issues.
2. It writes the snapshot atomically as JSON to the App Group container and calls `WidgetCenter.shared.reloadTimelines(ofKind:)`.
3. **When to write:**
   - A session starts, pauses, resumes or ends.
   - Today's issues or metrics change.
   - The day rolls over.
   - The connection is lost or regained, or the app quits (write a "not running" snapshot).
   - A heartbeat about every 15 minutes while connected.

   Coalesce writes and skip a write when nothing changed, to stay inside WidgetKit's reload budget.
4. **Expiry:** each snapshot carries `validUntil` (about 20 minutes ahead). The widget's timeline has a second entry at `validUntil` that shows "Not connected". So a crash, which the app can't record, is reflected within that window.
5. The widget only reads the file. Clicking it opens Crona through a URL or app activation.

**Why this approach:** only the app knows the connection state that the "not connected" rule depends on, and it already hears every change as it happens. So the widget can't disagree with the popover. The cost: no data while the app isn't running, even if the daemon is.

## Alternatives considered

### B. The widget talks to the daemon socket directly (possible later addition)

- The sandboxed widget reaches `~/.crona/.../kernel.sock` through a `com.apple.security.temporary-exception` entitlement. Outside the App Store this is permitted; only App Store review forbids such exceptions.
- **Gain:** it works without the app, for people who only use the CLI or TUI.
- **Costs:**
  - The widget only fetches when WidgetKit asks for a timeline, so it lags behind changes.
  - The socket path depends on `CRONA_HOME`, so the widget would have to repeat the app's discovery logic.
  - The widget would open its own daemon connections alongside the app's.
- **When to reconsider:** if users want the widget without running the menu bar app. It could then complement A: use A's snapshot when it is fresh, and fall back to the socket.

### C. The daemon writes the snapshot

- This works without the app, but needs changes in the Go repo, and the daemon would need to know the widget's container path. That couples the two repos for a macOS-only feature. Rejected.

## First step: signing spike (throwaway)

Before any real implementation, prove the riskiest assumption:

- An unsandboxed, Developer ID–signed app shares a team-prefixed App Group with a sandboxed widget extension, with no provisioning profile.
- Archived and exported the way `release.yml` does it, then installed on current macOS.

Check that:

1. The widget appears in the widget gallery.
2. The widget reads a file the app wrote to the group container.
3. No "access data from other apps" prompt appears.
4. Notarization and `codesign --verify --deep --strict` pass.

If any check fails, revisit the approach before writing the spec.

## Open questions for the spec

- The exact snapshot schema and its version field.
- What a click opens: the popover, or the popover on a specific issue.
- Habits in Medium, or keep it to issues.
- Heartbeat interval versus WidgetKit's reload budget.
- Tests: unit-test the snapshot builder and the write throttling in `cronaTests`. Widget views use SwiftUI previews only.
