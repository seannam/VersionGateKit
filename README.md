# VersionGateKit

A portable iOS force-update gate. Detects when the installed app is older than the latest App Store version (or a JSON-driven floor) and renders a non-dismissible blocker prompting users to update.

**How it works:** On launch (and again on foreground), VersionGateKit hits the iTunes Lookup endpoint, parses the latest published version, compares it to the installed version with a proper semantic comparison, and flips an `@Published` flag if an update is required. The host app renders a `ForceUpdateOverlay` (or applies `.versionGate()`) at the root of its view tree. Decisions are cached for 6 hours; any error fail-opens so transient outages never lock users out.

## Requirements

- iOS 16.0+
- Swift 5.9+

## Installation

### Swift Package Manager

**Xcode:** File > Add Package Dependencies > enter the repo URL:
```
https://github.com/seannam/VersionGateKit.git
```

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/seannam/VersionGateKit.git", from: "1.0.0")
]
```

**XcodeGen (`project.yml`):**
```yaml
packages:
  VersionGateKit:
    url: https://github.com/seannam/VersionGateKit.git
    from: 1.0.0

targets:
  MyApp:
    dependencies:
      - package: VersionGateKit
```

After adding the dependency, run `xcodegen generate` if using XcodeGen.

## Integration Guide

Integration touches 2 files in your app. Total: ~20 lines of code.

### Step 1: Configure at app launch

```swift
import SwiftUI
import VersionGateKit

@main
struct MyApp: App {
    @StateObject private var versionGate = VersionGateManager.shared

    init() {
        VersionGateManager.shared.configure(VersionGateKitConfig(
            bundleId: "com.example.myapp",
            appStoreId: "1234567890"
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(versionGate)
                .versionGate()
                .task { await VersionGateManager.shared.checkIfNeeded() }
        }
    }
}
```

`.versionGate()` wraps the receiver in a `ZStack` and overlays `ForceUpdateOverlay` whenever `requiresUpdate` is true.

### Step 2 (optional): Manual overlay placement

If you need finer control over z-ordering (for example, to keep the overlay above your own loading view), drop `ForceUpdateOverlay` into your root `ZStack` directly:

```swift
ZStack {
    MainContent()
    if versionGate.requiresUpdate {
        ForceUpdateOverlay()
            .zIndex(999)
    }
}
.environmentObject(versionGate)
```

### Step 3 (optional): JSON-driven floor

If you ship a remote-config or in-app JSON file with a minimum-version override, pass a `minimumVersionProvider` closure. The package re-evaluates it every time `checkIfNeeded()` runs:

```swift
VersionGateKitConfig(
    bundleId: "com.example.myapp",
    appStoreId: "1234567890",
    minimumVersionProvider: { ContentLoader.shared.config.forceUpdateMinimumVersion }
)
```

The required version is `max(latestAppStoreVersion, minimumVersionProvider())`, so the floor only ever raises the bar.

### Step 4 (optional): Re-check on foreground

```swift
NotificationCenter.default.addObserver(
    forName: UIApplication.willEnterForegroundNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        await VersionGateManager.shared.checkIfNeeded()
    }
}
```

## Theming

Every color and copy string on the overlay is configurable via `VersionGateKitConfig`:

```swift
VersionGateKitConfig(
    bundleId: "...",
    appStoreId: "...",
    accentColor: .yellow,
    backgroundColor: .black,
    cardColor: .gray,
    textPrimaryColor: .white,
    textSecondaryColor: .gray,
    iconEmoji: "🍋",
    headlineText: "Update Required",
    bodyText: "A new version is available. Please update to keep playing.",
    buttonLabel: "Update Now"
)
```

All theme tokens have sensible defaults (`Color(uiColor: .systemBackground)`, `.primary`, etc.) so an unstyled integration still looks reasonable in light and dark mode.

## Behavior

- **Cache TTL:** 6 hours by default. Override via `VersionGateKitConfig(cacheTTL:)`.
- **Cache key:** `\(userDefaultsSuitePrefix)_cache`. Default prefix is `versiongatekit`. Override per app to avoid collisions when multiple targets share a UserDefaults suite.
- **Cache invalidation:** Stored decisions are bound to the `installedVersion` they were computed for. After a fresh update, the cache is silently dropped so the user never sees a stale `requiresUpdate=true`.
- **Fail-open:** Any network error, decoding failure, or missing `version` field results in `requiresUpdate=false` and a fresh failure cache (so we don't hammer the endpoint on retry).
- **App Store launcher:** `openAppStore()` prefers `itms-apps://` (opens the in-app store sheet), falling back to `https://apps.apple.com/...` if the URL scheme is unavailable.
- **Malformed installed version:** If `Bundle.main`'s `CFBundleShortVersionString` (or whatever you pass for `installedVersion`) doesn't parse as a `SemanticVersion`, the package treats it as `.zero`, so any positive store version will trigger the gate. Pin a known-good version string in `installedVersion` if you need to test the rejection path.

## FAQ

### Why doesn't the overlay show on a fresh install?
Apple's iTunes Lookup endpoint returns the latest published version. If your fresh install is already on that version, `requiresUpdate` stays false. To smoke-test the overlay locally, pass a `minimumVersionProvider` that returns a deliberately-high version like `"99.0.0"` and clear UserDefaults to bust the cache.

### How do I test it locally?
Inject a custom `URLSession` (the package's `init` accepts one) backed by a `URLProtocol` stub. The package's own test target uses this exact pattern in `MockURLProtocol` to exercise the success and failure paths end-to-end.

### Does it work on macOS / tvOS?
The package compiles on iOS 16, macOS 14, and tvOS 16. The App Store launcher (`openAppStore()`) is gated behind `#if canImport(UIKit) && !os(watchOS)` so the overlay still renders on macOS but the launch is a no-op there. The same applies to tvOS.

### How do I gate the overlay on a closure other than `minimumVersionProvider`?
Use `manager.requiresUpdate` directly in your own SwiftUI view. The published flag is the single source of truth; the bundled `ForceUpdateOverlay` is just one possible presentation.
