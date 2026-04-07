import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Enforcement

/// Settings that shape the `.reminder` enforcement mode.
public struct VersionGateReminderSettings {
    public var snoozeDuration: TimeInterval
    public var dismissButtonLabel: String

    public init(
        snoozeDuration: TimeInterval = 24 * 3600,
        dismissButtonLabel: String = "Later"
    ) {
        self.snoozeDuration = snoozeDuration
        self.dismissButtonLabel = dismissButtonLabel
    }
}

/// Settings that shape the `.aggressive` enforcement mode.
public struct VersionGateAggressiveSettings {
    public var dismissButtonLabel: String
    public var dismissDelay: TimeInterval

    public init(
        dismissButtonLabel: String = "Later",
        dismissDelay: TimeInterval = 3.0
    ) {
        self.dismissButtonLabel = dismissButtonLabel
        self.dismissDelay = dismissDelay
    }
}

/// Strictness level for the update gate.
///
/// - `.required` (default) is today's behavior: non-dismissible blocker.
/// - `.reminder` is a polite, dismissible prompt whose dismissal persists for
///   the configured snooze window.
/// - `.aggressive` shows a blocker whose "Later" button unlocks after a short
///   forced delay; the dismissal is in-memory only and reappears on next check.
public enum VersionGateEnforcement {
    case reminder(VersionGateReminderSettings)
    case aggressive(VersionGateAggressiveSettings)
    case required

    public static let reminder: Self = .reminder(.init())
    public static let aggressive: Self = .aggressive(.init())
}

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
    public var enforcement: VersionGateEnforcement

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
        enforcement: VersionGateEnforcement = .required,
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
        self.enforcement = enforcement
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
