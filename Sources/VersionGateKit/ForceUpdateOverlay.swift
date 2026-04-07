import SwiftUI

/// Full-screen, non-dismissible overlay shown when the app is on a version
/// older than the App Store / configured floor. Render as a sibling in the
/// root `ZStack` (NOT a sheet) so the user truly cannot dismiss it, or use
/// the `View.versionGate(_:)` modifier for a one-line install.
public struct ForceUpdateOverlay: View {
    @EnvironmentObject private var manager: VersionGateManager

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
            }
            .padding()
        }
        // Block any taps from reaching the underlying UI.
        .contentShape(Rectangle())
        .onTapGesture { }
    }
}
