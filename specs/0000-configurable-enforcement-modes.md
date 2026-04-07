# Feature: Configurable Enforcement Modes for the Update Gate

## Feature Description
VersionGateKit currently ships a single behavior: when the installed version is older than the App Store / configured floor, it renders a fully non-dismissible blocker. That works for "must update to keep using" situations, but it is overkill for apps that simply want to nudge users about an available update or to escalate pressure gradually.

This feature introduces a `VersionGateEnforcement` configuration that lets host apps choose one of three strictness levels:

1. **`.reminder`** — A polite, dismissible prompt. Users tap "Later" and the app keeps working. Dismissals are persisted with a snooze TTL so the prompt doesn't reappear every launch.
2. **`.aggressive`** — A blocker that *appears* required but allows dismissal after a short forced delay (think: 3 second countdown). The dismissal does not snooze; the overlay reappears on every check.
3. **`.required`** *(default)* — Today's behavior. Non-dismissible, no escape hatch. This is the default value so every existing integration continues to behave identically with zero source changes.

Each mode carries its own associated settings struct (snooze duration, "Later" label, forced delay, etc.) with defaults, so the simplest call site stays a one-liner.

## User Story
As an iOS developer integrating VersionGateKit
I want to configure how strictly the update gate enforces a new version
So that I can match the gate's pressure to the kind of update I'm shipping (optional polish vs. critical security fix) without forking the package or building my own overlay.

## Problem Statement
The current API is binary: either the gate blocks the user completely or you don't ship it at all. Real apps need a spectrum:

- **Marketing/UX teams** want a gentle "hey, there's a new version" reminder for non-critical updates that respects the user's right to keep working.
- **Product teams** rolling out a high-priority (but not mandatory) update want something more in-your-face than a banner but less hostile than a hard wall — an overlay that visibly delays the user but ultimately lets them continue.
- **Security/compliance** updates need today's hard wall.

There is also no notion of "snooze" — if the host app wanted to build a reminder UI today, it would need to wrap or replace `ForceUpdateOverlay` and re-implement persistence on top of `requiresUpdate`. The package owns the only convenient UserDefaults cache key, so this work would either duplicate state or fight the manager.

## Solution Statement
Introduce a `VersionGateEnforcement` enum with associated settings, threaded through `VersionGateKitConfig`, the manager, and the bundled overlay. The manager exposes a new published `isDismissed` flag plus a `dismiss()` action; the overlay reads the active enforcement mode and conditionally renders a "Later" button (with optional countdown) based on it. Snooze state is persisted in the existing UserDefaults cache record so we don't introduce a second persistence surface.

Default value is `.required`, which preserves the exact current behavior — no existing integration needs to change a single line. The only externally visible changes for existing users are additive: a new field on the config (with a default), a new published property, and a new method on the manager.

## Relevant Files
Use these files to implement the feature:

- `Sources/VersionGateKit/VersionGateKitConfig.swift` — Holds all knobs the host app passes in. We add `enforcement: VersionGateEnforcement` here with a `.required` default plus a new initializer parameter (also defaulted) so the existing `init` call sites stay source-compatible.
- `Sources/VersionGateKit/VersionGateManager.swift` — Owns the decision and the cache. We add `isDismissed` state, a `dismiss()` method, a `lastDismissedAt`/`dismissedForVersion` field on `CachedDecision`, and snooze-aware logic in `apply(...)` so `.reminder` doesn't re-show within the snooze window.
- `Sources/VersionGateKit/ForceUpdateOverlay.swift` — Renders the gate. We branch on `manager.config.enforcement` to optionally show a "Later" button (with a countdown for `.aggressive`), wire it to `manager.dismiss()`, and keep the current `.required` rendering identical for backwards compatibility.
- `Sources/VersionGateKit/View+VersionGate.swift` — The `versionGate()` modifier currently shows the overlay when `requiresUpdate` is true. It needs to additionally hide the overlay when `isDismissed` is true (so a snoozed reminder doesn't reappear within the same session).
- `Tests/VersionGateKitTests/VersionGateKitTests.swift` — All existing behavior tests must keep passing (proves backwards compatibility) and we add new tests for each enforcement mode and snooze behavior.
- `Tests/VersionGateKitTests/MockURLProtocol.swift` — Existing test infra; reused as-is.
- `README.md` — Documents public API. We add a "Enforcement Modes" section under "Behavior".

### New Files
None. The feature fits cleanly into the existing 5-file package surface; introducing new files would fragment the API for what is essentially a new enum and a new method.

## Implementation Plan

### Phase 1: Foundation
Define the `VersionGateEnforcement` enum and its associated settings structs in `VersionGateKitConfig.swift`. Make every field default so call sites can write `.reminder()` with no arguments. Wire the new field through `VersionGateKitConfig.init` as a defaulted parameter (`enforcement: VersionGateEnforcement = .required`) so the public initializer remains source-compatible. Extend `CachedDecision` with `dismissedAt: TimeInterval?` and `dismissedForVersion: String?` as optional fields so old cached records (encoded before this feature) decode cleanly.

### Phase 2: Core Implementation
Add `@Published private(set) var isDismissed: Bool` to `VersionGateManager`. Implement `func dismiss()` which:
- Returns immediately if `enforcement == .required` (defensive guard).
- Sets `isDismissed = true`.
- For `.reminder`, updates the cache record's `dismissedAt`/`dismissedForVersion` and resaves so the snooze persists across launches.
- For `.aggressive`, only flips the in-memory flag (no persistence — overlay must reappear on next check).

In `checkIfNeeded()`, after computing `shouldBlock`, consult the cache for an active `.reminder` snooze: if `dismissedForVersion == latestRequiredVersion` and `Date().timeIntervalSince1970 - dismissedAt < reminderSettings.snoozeDuration`, set `isDismissed = true` so the overlay stays hidden. The snooze is bound to a specific required version so a *newer* App Store release re-arms the prompt automatically.

Update `ForceUpdateOverlay` to branch on `manager.config.enforcement`:
- `.required`: render exactly as today.
- `.reminder(let settings)`: render today's layout plus a secondary "Later" button (label from `settings.dismissButtonLabel`) wired to `manager.dismiss()`. The "Later" button uses `textSecondaryColor` styling so it reads as the lower-priority action.
- `.aggressive(let settings)`: render today's layout, plus a "Later" button that is *disabled* until `settings.dismissDelay` seconds have elapsed (driven by a `Task` that flips a local `@State` flag). After the delay, tapping "Later" calls `manager.dismiss()`.

Update `View+VersionGate.swift`'s container to overlay the gate when `manager.requiresUpdate && !manager.isDismissed` (instead of just `requiresUpdate`).

### Phase 3: Integration
Verify that the existing public API surface compiles unchanged: `VersionGateKitConfig(bundleId:appStoreId:)` must still work, `manager.requiresUpdate` must still be the source of truth for "is there an update available", and the bundled overlay must still render identically when `enforcement` is left at its default. Add tests covering: default-mode parity, reminder dismissal + snooze persistence, snooze invalidation when the required version moves, aggressive-mode dismissal not persisting, and `dismiss()` being a no-op under `.required`. Update `README.md` with a new "Enforcement Modes" subsection showing each mode's call site.

## Step by Step Tasks
IMPORTANT: Execute every step in order, top to bottom.

### 1. Add the `VersionGateEnforcement` enum and settings structs
- In `Sources/VersionGateKit/VersionGateKitConfig.swift`, above `VersionGateKitConfig`, add:
  - `public struct VersionGateReminderSettings` with `snoozeDuration: TimeInterval = 24 * 3600`, `dismissButtonLabel: String = "Later"`, and a public memberwise `init` with defaults for every field.
  - `public struct VersionGateAggressiveSettings` with `dismissButtonLabel: String = "Later"`, `dismissDelay: TimeInterval = 3.0`, and a public memberwise `init` with defaults.
  - `public enum VersionGateEnforcement` with cases `.reminder(VersionGateReminderSettings)`, `.aggressive(VersionGateAggressiveSettings)`, `.required`. Add static convenience factories `static let reminder: Self = .reminder(.init())` and `static let aggressive: Self = .aggressive(.init())` so call sites can write `.reminder` without parens.

### 2. Thread `enforcement` through `VersionGateKitConfig`
- Add `public var enforcement: VersionGateEnforcement` stored property.
- Add `enforcement: VersionGateEnforcement = .required` to the `init` signature, placed after `minimumVersionProvider` to keep theme/copy params at the end of the parameter list (existing trailing-default callers stay valid).
- Assign it in the initializer body.

### 3. Extend `CachedDecision` with snooze fields
- In `Sources/VersionGateKit/VersionGateManager.swift`, add `var dismissedAt: TimeInterval?` and `var dismissedForVersion: String?` to `CachedDecision`. Both must be optional with `nil` default so previously-encoded cache blobs (which lack these keys) still decode via `JSONDecoder`'s default behavior.
- Update the existing memberwise usages of `CachedDecision` to pass `dismissedAt: nil, dismissedForVersion: nil` where appropriate (or rely on defaults if you make the init explicit).

### 4. Add `isDismissed` published state and `dismiss()` to the manager
- Add `@Published public private(set) var isDismissed: Bool = false`.
- Add `public func dismiss()`:
  - Switch on `config.enforcement`.
  - `.required`: return (no-op, cannot bypass a required gate).
  - `.aggressive`: set `isDismissed = true`.
  - `.reminder`: set `isDismissed = true`, then load the existing cached decision (if any), update its `dismissedAt = Date().timeIntervalSince1970` and `dismissedForVersion = latestAppStoreVersion`, and resave.

### 5. Honor snooze in `checkIfNeeded()`
- In `checkIfNeeded()`, immediately after `apply(requiresUpdate:latestVersion:)` is called from the cache hit path (and from the network success path), evaluate snooze:
  - If `config.enforcement` is `.reminder(let settings)`, `requiresUpdate == true`, and the cached record has `dismissedAt != nil`, `dismissedForVersion == latestAppStoreVersion`, and `now - dismissedAt < settings.snoozeDuration`, set `isDismissed = true`.
  - Otherwise set `isDismissed = false`.
- Whenever a *new* required version is observed, the snooze is automatically considered stale by the version mismatch check, so no extra invalidation is needed.

### 6. Update the `View+VersionGate` container
- In `Sources/VersionGateKit/View+VersionGate.swift`, change the overlay condition from `if manager.requiresUpdate` to `if manager.requiresUpdate && !manager.isDismissed`.
- Leave the rest of the container untouched.

### 7. Branch the `ForceUpdateOverlay` on enforcement mode
- In `Sources/VersionGateKit/ForceUpdateOverlay.swift`, add `@State private var dismissCountdown: TimeInterval = 0` and `@State private var dismissEnabled: Bool = false` to drive the aggressive-mode delay.
- After the existing primary `Update Now` button, add a `@ViewBuilder` private helper `dismissButton(for enforcement: VersionGateEnforcement)` that renders:
  - `EmptyView()` for `.required`.
  - A plain text button using `settings.dismissButtonLabel` and `config.textSecondaryColor` for `.reminder`, wired to `manager.dismiss()`.
  - For `.aggressive`, the same button but `.disabled(!dismissEnabled)` and overlaid with a countdown (e.g., `"Later (\(Int(remaining)))"`) until the delay elapses; then it becomes tappable and calls `manager.dismiss()`.
- Use `.task(id: enforcementCaseTag)` (or `.onAppear`) to start the aggressive-mode countdown so it resets if the overlay re-appears.
- Keep the `.contentShape(Rectangle()).onTapGesture {}` swallow for `.required` only — for `.reminder`/`.aggressive` it is still fine to keep it (the only escape remains the explicit "Later" button), so you can leave the modifier in place unconditionally.

### 8. Add unit tests for the enum and settings defaults
- In `Tests/VersionGateKitTests/VersionGateKitTests.swift`, add:
  - `testEnforcementDefaultsToRequired()` — constructs `VersionGateKitConfig(bundleId:appStoreId:)` and asserts the new field equals `.required` (use a switch + `XCTFail` since the enum has no auto-`Equatable`).
  - `testReminderSettingsDefaults()` — asserts the snooze duration default is `24 * 3600` and label is `"Later"`.
  - `testAggressiveSettingsDefaults()` — asserts `dismissDelay == 3.0`.

### 9. Add manager-level tests for `dismiss()` semantics
- `testDismissIsNoOpUnderRequired()` — configure the manager with default enforcement, force `requiresUpdate = true` via the network success path, call `dismiss()`, assert `isDismissed == false`.
- `testDismissUnderReminderSetsFlagAndPersists()` — configure with `.reminder(.init(snoozeDuration: 3600))`, run a successful network check that yields `requiresUpdate == true`, call `dismiss()`, assert `isDismissed == true`, then construct a *fresh* manager pointing at the same `UserDefaults` and assert that after `checkIfNeeded()` the new instance also reports `isDismissed == true` (proves snooze persisted).
- `testReminderSnoozeExpiresAfterTTL()` — same setup but pre-seed a cache where `dismissedAt` is older than `snoozeDuration`. After `checkIfNeeded()`, assert `isDismissed == false` (and `requiresUpdate == true` so the overlay would show again).
- `testReminderSnoozeInvalidatedByNewerStoreVersion()` — pre-seed a cache where `dismissedForVersion = "5.0.0"`, run a network check that returns `9.9.9`, assert `isDismissed == false`.
- `testDismissUnderAggressiveDoesNotPersist()` — configure with `.aggressive`, dismiss, then create a fresh manager on the same `UserDefaults` and assert `isDismissed == false` after a fresh check.

### 10. Add a backwards-compat regression test
- `testExistingInitSignatureStillCompiles()` — call `VersionGateKitConfig(bundleId: "x", appStoreId: "y")` and `VersionGateKitConfig(bundleId: "x", appStoreId: "y", installedVersion: "1.0.0", cacheTTL: 60, userDefaultsSuitePrefix: "p", minimumVersionProvider: { nil })`. The point is purely to fail compilation if the parameter order is broken; runtime asserts can be trivial.

### 11. Update the README
- Under the existing "Behavior" section in `README.md`, add a new subsection titled "Enforcement Modes" that documents `.required` (default), `.reminder`, and `.aggressive` with one short Swift snippet per mode and a one-line description of when to use each. Also add a one-line note that `manager.dismiss()` is a no-op under `.required`.

### 12. Run the validation commands
- Execute every command in the `Validation Commands` section below from the package root and confirm zero errors and zero failing tests.

## Testing Strategy

### Unit Tests
- Enum/struct default values (`testEnforcementDefaultsToRequired`, `testReminderSettingsDefaults`, `testAggressiveSettingsDefaults`).
- `dismiss()` is a no-op under `.required`.
- `dismiss()` flips `isDismissed` under `.reminder` and `.aggressive`.
- Cached `dismissedAt`/`dismissedForVersion` round-trips through `JSONEncoder`/`JSONDecoder`.

### Integration Tests
- Reminder snooze persists across manager instances sharing a `UserDefaults`.
- Reminder snooze is invalidated when the network reports a newer required version.
- Reminder snooze expires after `snoozeDuration`.
- Aggressive-mode dismissal does NOT persist across manager instances.
- All existing tests in `VersionGateKitTests.swift` continue to pass unmodified (proves backwards compatibility of the public API).

### Edge Cases
- Old `CachedDecision` records on disk (encoded before this feature) decode cleanly because the new fields are optional.
- A user dismisses under `.reminder`, then the app is reconfigured to `.required` on next launch; the gate must show (because `dismiss()` is a no-op under `.required` and `checkIfNeeded()` only honors snooze when the *current* enforcement is `.reminder`).
- A user dismisses under `.reminder`, the snooze TTL passes, and `checkIfNeeded()` runs from cache (not network) — snooze must still expire correctly because TTL is checked against `dismissedAt`, independent of the cache's own TTL.
- Aggressive-mode countdown should reset if the overlay disappears and reappears in the same session (avoid the user getting a "free" instant-dismiss after one full delay).
- `dismiss()` called before `checkIfNeeded()` (i.e., before any cache record exists) under `.reminder`: should still flip the in-memory flag without crashing; persistence becomes a no-op (no record to update).

## Acceptance Criteria
- `VersionGateKitConfig(bundleId:appStoreId:)` continues to compile and behave identically to the pre-feature build (default `.required` mode).
- A host app can opt into `.reminder` mode and the bundled overlay shows a "Later" button that dismisses the gate for the configured snooze window.
- A host app can opt into `.aggressive` mode and the "Later" button is disabled until the configured `dismissDelay` elapses, after which it dismisses the overlay for the current session only.
- `manager.dismiss()` is a no-op under `.required`.
- `manager.isDismissed` is exposed as a `@Published` read-only property and is honored by both the bundled overlay and the `versionGate()` modifier.
- All existing tests in `VersionGateKitTests.swift` pass without modification.
- All new tests listed in steps 8–10 pass.
- `swift build` succeeds with zero warnings.
- `README.md` documents the new modes.

## Validation Commands
Execute every command to validate the feature works correctly with zero regressions.

- `cd /Users/seannam/Developer/VersionGateKit && swift build` — Compile the package; must succeed with zero errors and no new warnings.
- `cd /Users/seannam/Developer/VersionGateKit && swift test` — Run the full XCTest suite; every existing test plus the new ones from steps 8–10 must pass.
- `cd /Users/seannam/Developer/VersionGateKit && swift test --filter testEnforcementDefaultsToRequired` — Spot-check that the default-mode regression test runs and passes.
- `cd /Users/seannam/Developer/VersionGateKit && swift test --filter testDismissUnderReminderSetsFlagAndPersists` — Spot-check the reminder snooze persistence path end-to-end.
- `cd /Users/seannam/Developer/VersionGateKit && swift test --filter testDismissUnderAggressiveDoesNotPersist` — Spot-check that aggressive dismissal stays in-memory only.

## Notes
- No new dependencies. Everything fits inside the existing 5-source-file package and reuses the existing `MockURLProtocol`-based test harness.
- We deliberately store snooze state inside the existing `CachedDecision` UserDefaults blob rather than introducing a second persistence key. This keeps the cache key surface (`{prefix}_cache`) unchanged and makes snooze automatically participate in the existing "installed version changed -> drop cache" invalidation. Apps that already configure a `userDefaultsSuitePrefix` get the same isolation guarantee for free.
- `VersionGateEnforcement` is intentionally non-`Equatable` initially; tests that need to compare it should switch over the cases. If a future feature needs `Equatable`/`Codable` (e.g., to drive enforcement from remote config), the synthesis can be added at that point — adding it now is speculative.
- The aggressive-mode countdown is implemented in pure SwiftUI inside the overlay and does not require any additional manager state. This keeps the manager API minimal and lets the host app drop in a custom overlay (using `manager.requiresUpdate` + `manager.config.enforcement` + `manager.dismiss()`) without re-implementing manager plumbing.
- Future consideration: a `.scheduled(date:)` mode that escalates from `.reminder` to `.required` after a certain date (useful for "you have until X to update before this becomes mandatory" rollouts). Out of scope here but the enum shape supports adding it without breaking existing call sites because `.required` stays the default.
