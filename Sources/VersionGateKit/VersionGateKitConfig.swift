import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Configuration

/// Configuration for VersionGateKit. Provide app-specific values at launch.
/// Only `bundleId` and `appStoreId` are required; everything else has a default.
public struct VersionGateKitConfig {
    public let bundleId: String
    public let appStoreId: String
    public var installedVersion: String
    public var cacheTTL: TimeInterval
    public var userDefaultsSuitePrefix: String
    public var minimumVersionProvider: (() -> String?)?

    // Theme tokens
    public var accentColor: Color
    public var backgroundColor: Color
    public var cardColor: Color
    public var textPrimaryColor: Color
    public var textSecondaryColor: Color

    // Copy
    public var iconEmoji: String
    public var headlineText: String
    public var bodyText: String
    public var buttonLabel: String

    public init(
        bundleId: String,
        appStoreId: String,
        installedVersion: String = {
            (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        }(),
        cacheTTL: TimeInterval = 6 * 3600,
        userDefaultsSuitePrefix: String = "versiongatekit",
        minimumVersionProvider: (() -> String?)? = nil,
        accentColor: Color = .yellow,
        backgroundColor: Color = {
            #if os(tvOS)
            return Color.black
            #elseif canImport(UIKit)
            return Color(uiColor: .systemBackground)
            #else
            return Color(NSColor.windowBackgroundColor)
            #endif
        }(),
        cardColor: Color = {
            #if os(tvOS)
            return Color(white: 0.15)
            #elseif canImport(UIKit)
            return Color(uiColor: .secondarySystemBackground)
            #else
            return Color(NSColor.controlBackgroundColor)
            #endif
        }(),
        textPrimaryColor: Color = .primary,
        textSecondaryColor: Color = .secondary,
        iconEmoji: String = "⬆️",
        headlineText: String = "Update Required",
        bodyText: String = "A new version of this app is available. Please update to keep using it.",
        buttonLabel: String = "Update Now"
    ) {
        self.bundleId = bundleId
        self.appStoreId = appStoreId
        self.installedVersion = installedVersion
        self.cacheTTL = cacheTTL
        self.userDefaultsSuitePrefix = userDefaultsSuitePrefix
        self.minimumVersionProvider = minimumVersionProvider
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.cardColor = cardColor
        self.textPrimaryColor = textPrimaryColor
        self.textSecondaryColor = textSecondaryColor
        self.iconEmoji = iconEmoji
        self.headlineText = headlineText
        self.bodyText = bodyText
        self.buttonLabel = buttonLabel
    }

    // MARK: - Derived URLs

    public var lookupURL: URL {
        URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)")!
    }

    public var appStoreURL: URL {
        URL(string: "itms-apps://apps.apple.com/app/id\(appStoreId)")!
    }

    public var appStoreWebURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreId)")!
    }
}
