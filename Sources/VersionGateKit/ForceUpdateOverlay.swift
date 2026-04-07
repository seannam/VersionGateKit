import SwiftUI

/// Full-screen, non-dismissible overlay shown when the app is on a version
/// older than the App Store / configured floor. Render as a sibling in the
/// root `ZStack` (NOT a sheet) so the user truly cannot dismiss it, or use
/// the `View.versionGate(_:)` modifier for a one-line install.
public struct ForceUpdateOverlay: View {
    @EnvironmentObject private var manager: VersionGateManager
    @State private var dismissEnabled: Bool = false
    @State private var dismissRemaining: TimeInterval = 0

    public init() {}

    public var body: some View {
        let config = manager.config

        ZStack {
            config.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text(config.iconEmoji)
                    .font(.system(size: 80))

                Text(config.headlineText)
                    .font(.largeTitle.bold())
                    .foregroundColor(config.textPrimaryColor)
                    .multilineTextAlignment(.center)

                Text(config.bodyText)
                    .font(.body)
                    .foregroundColor(config.textSecondaryColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let latest = manager.latestAppStoreVersion {
                    HStack(spacing: 8) {
                        Text("v\(manager.installedVersion)")
                            .foregroundColor(config.textSecondaryColor)
                        Image(systemName: "arrow.right")
                            .foregroundColor(config.textSecondaryColor)
                        Text("v\(latest)")
                            .foregroundColor(config.accentColor)
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }

                Button(action: {
                    manager.openAppStore()
                }) {
                    Text(config.buttonLabel)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(config.accentColor)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)

                dismissButton(for: config.enforcement, config: config)
            }
            .padding()
        }
        // Block any taps from reaching the underlying UI.
        .contentShape(Rectangle())
        .onTapGesture { }
        .task(id: enforcementTag(config.enforcement)) {
            await runAggressiveCountdownIfNeeded(config.enforcement)
        }
    }

    @ViewBuilder
    private func dismissButton(
        for enforcement: VersionGateEnforcement,
        config: VersionGateKitConfig
    ) -> some View {
        switch enforcement {
        case .required:
            EmptyView()
        case .reminder(let settings):
            Button(action: { manager.dismiss() }) {
                Text(settings.dismissButtonLabel)
                    .font(.subheadline)
                    .foregroundColor(config.textSecondaryColor)
                    .padding(.vertical, 8)
            }
            .padding(.top, 4)
        case .aggressive(let settings):
            Button(action: { manager.dismiss() }) {
                Text(dismissEnabled
                     ? settings.dismissButtonLabel
                     : "\(settings.dismissButtonLabel) (\(Int(ceil(dismissRemaining))))")
                    .font(.subheadline)
                    .foregroundColor(config.textSecondaryColor)
                    .padding(.vertical, 8)
            }
            .disabled(!dismissEnabled)
            .padding(.top, 4)
        }
    }

    private func enforcementTag(_ enforcement: VersionGateEnforcement) -> Int {
        switch enforcement {
        case .required: return 0
        case .reminder: return 1
        case .aggressive: return 2
        }
    }

    private func runAggressiveCountdownIfNeeded(_ enforcement: VersionGateEnforcement) async {
        guard case .aggressive(let settings) = enforcement else {
            dismissEnabled = true
            return
        }
        dismissEnabled = false
        dismissRemaining = settings.dismissDelay
        let start = Date()
        while true {
            let elapsed = Date().timeIntervalSince(start)
            let remaining = settings.dismissDelay - elapsed
            if remaining <= 0 {
                dismissRemaining = 0
                dismissEnabled = true
                return
            }
            dismissRemaining = remaining
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                return
            }
        }
    }
}
