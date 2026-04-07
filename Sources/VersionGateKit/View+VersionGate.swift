import SwiftUI

@MainActor
public extension View {
    /// Wraps the receiver in a `ZStack` that overlays `ForceUpdateOverlay`
    /// whenever `manager.requiresUpdate` is `true`. Injects `manager` as an
    /// `environmentObject` so the overlay can read its state.
    func versionGate(_ manager: VersionGateManager = .shared) -> some View {
        VersionGateContainer(manager: manager) { self }
    }
}

private struct VersionGateContainer<Content: View>: View {
    @ObservedObject var manager: VersionGateManager
    let content: () -> Content

    var body: some View {
        ZStack {
            content()

            if manager.requiresUpdate {
                ForceUpdateOverlay()
                    .zIndex(999)
                    .transition(.opacity)
            }
        }
        .environmentObject(manager)
    }
}
