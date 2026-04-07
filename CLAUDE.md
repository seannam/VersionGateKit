# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VersionGateKit is a single-product Swift Package (`Package.swift`) that ships an iOS/macOS/tvOS force-update gate. The library has zero external dependencies. Platforms: iOS 16+, macOS 14+, tvOS 16+, Swift 5.9+.

## Commands

```bash
swift build                                          # build library
swift test                                           # run all tests
swift test --filter VersionGateKitTests.<TestName>   # run a single test
```

There is no separate lint config; rely on the Swift compiler.

## Architecture

The package is intentionally small (~5 source files). Understand these pieces together:

- **`VersionGateManager`** (`Sources/VersionGateKit/VersionGateManager.swift`) is the only stateful component. It is a `@MainActor`, `ObservableObject` singleton (`.shared`) that publishes `requiresUpdate`, `isDismissed`, `latestAppStoreVersion`, and `config`. Hosts call `configure(_:)` once at launch then `await checkIfNeeded()` to drive a fetch. Persistence is `UserDefaults`-only (key: `"\(userDefaultsSuitePrefix)_cache"`), and the manager owns the `CachedDecision` model + `LookupResponse` decoding.
- **Failure-mode is fail-open by design.** Any network error, decode failure, or missing `version` field calls `applyFailOpen()`, which clears `requiresUpdate` and writes a fresh failure cache so retries don't hammer the iTunes endpoint. Do not introduce throwing variants or surfaces that lock users out on transient errors.
- **Cache invalidation hinges on `installedVersion`.** `loadCache()` discards any decision whose stored `installedVersion` no longer matches the current bundle version, so a post-update launch never inherits a stale `requiresUpdate=true`. Preserve this invariant when touching cache code.
- **Snooze carry-over.** When a fresh fetch produces a new decision, `checkIfNeeded()` only carries over `dismissedAt`/`dismissedForVersion` if the new `latestAppStoreVersion` matches the existing cache; a newer store release auto-rearms the prompt. `evaluateSnooze(from:)` is the single place that flips `isDismissed` based on the snooze window.
- **`VersionGateKitConfig`** (`VersionGateKitConfig.swift`) is a value type holding everything app-specific: ids, theme tokens, copy, `cacheTTL`, `userDefaultsSuitePrefix`, `minimumVersionProvider`, and `enforcement`. It also computes the iTunes lookup URL and both `itms-apps://` and `https://` App Store URLs. New configurable behavior should land here as a defaulted parameter, not as a new public API on the manager.
- **`VersionGateEnforcement`** has three cases: `.required` (non-dismissible; `dismiss()` is a no-op), `.reminder(VersionGateReminderSettings)` (persisted snooze, default 24h), `.aggressive(VersionGateAggressiveSettings)` (in-memory dismissal, button locked for `dismissDelay` seconds, default 3s). The static helpers `.reminder` and `.aggressive` build the default settings. Default enforcement is `.required` so existing integrations don't change behavior.
- **`SemanticVersion`** (`SemanticVersion.swift`) is a 4-component comparable struct used to compare installed vs store vs `minimumVersionProvider()`. The required version is `max(storeVersion, configFloor)`. Strings that fail to parse become `.zero`, which intentionally causes any positive store version to trigger the gate (this is the documented test seam — see README "Malformed installed version").
- **UI surface.** `ForceUpdateOverlay` is a SwiftUI view that reads the manager from `@EnvironmentObject`. `View.versionGate(_:)` (`View+VersionGate.swift`) wraps the receiver in a private `VersionGateContainer` that ZStacks the overlay above content when `requiresUpdate && !isDismissed` and injects the manager as an environment object. Hosts can also place `ForceUpdateOverlay` manually for custom z-ordering.
- **Tests** use `MockURLProtocol` (`Tests/VersionGateKitTests/MockURLProtocol.swift`) to stub `URLSession` responses end-to-end. New manager tests should construct a `VersionGateManager(session:userDefaults:)` with a fresh in-memory `UserDefaults(suiteName:)` and a `URLSession` configured with `MockURLProtocol`, mirroring the existing pattern.

## Conventions

- Conventional commit message format (see existing history: `feat:`, `chore:`).
- Never use em dashes in prose.
- The README is the user-facing integration guide; keep it in sync when public API on `VersionGateKitConfig`, `VersionGateEnforcement`, or `VersionGateManager` changes.
