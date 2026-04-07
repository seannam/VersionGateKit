import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Self-contained force-update manager. Owns its persistence via UserDefaults
/// and has zero dependencies on any app-specific code.
///
/// Failure-mode: any network error, decoding failure, or missing data is
/// treated as "do not block". We never lock users out due to transient
/// outages or schema changes on Apple's lookup endpoint.
@MainActor
public final class VersionGateManager: ObservableObject {

    public static let shared = VersionGateManager()

    // MARK: - Published State

    @Published public private(set) var requiresUpdate: Bool = false
    @Published public private(set) var latestAppStoreVersion: String? = nil
    @Published public private(set) var config: VersionGateKitConfig

    public var installedVersion: String { config.installedVersion }

    // MARK: - Dependencies

    private let session: URLSession
    private let userDefaults: UserDefaults
    private var hasWarnedUnconfigured = false

    // MARK: - Init

    public init(
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.session = session
        self.userDefaults = userDefaults
        self.config = VersionGateKitConfig(bundleId: "", appStoreId: "")
    }

    // MARK: - Configuration

    public func configure(_ config: VersionGateKitConfig) {
        self.config = config
    }

    // MARK: - Public API

    /// Reads cache, or fetches the latest App Store version and updates
    /// `requiresUpdate`. Safe to call repeatedly; respects the cache TTL.
    public func checkIfNeeded() async {
        guard !config.bundleId.isEmpty else {
            if !hasWarnedUnconfigured {
                print("[VersionGateKit] checkIfNeeded() called before configure(); skipping.")
                hasWarnedUnconfigured = true
            }
            return
        }

        if let cached = loadCache(), !cached.isExpired(ttl: config.cacheTTL) {
            apply(requiresUpdate: cached.requiresUpdate, latestVersion: cached.latestAppStoreVersion)
            return
        }

        do {
            let (data, _) = try await session.data(from: config.lookupURL)
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let appStoreVersionString = response.results.first?.version else {
                applyFailOpen()
                return
            }
            let storeVersion = SemanticVersion(appStoreVersionString) ?? .zero
            let configFloor = config.minimumVersionProvider?().flatMap(SemanticVersion.init) ?? .zero
            let required = max(storeVersion, configFloor)
            let installed = SemanticVersion(installedVersion) ?? .zero
            let shouldBlock = installed < required

            apply(requiresUpdate: shouldBlock, latestVersion: appStoreVersionString)
            saveCache(CachedDecision(
                requiresUpdate: shouldBlock,
                latestAppStoreVersion: appStoreVersionString,
                installedVersion: installedVersion,
                timestamp: Date().timeIntervalSince1970
            ))
        } catch {
            applyFailOpen()
        }
    }

    /// Opens the App Store product page. Prefers `itms-apps://` so the
    /// store opens in-app, falling back to the https URL if unavailable.
    public func openAppStore() {
        #if canImport(UIKit) && !os(watchOS)
        let primary = config.appStoreURL
        if UIApplication.shared.canOpenURL(primary) {
            UIApplication.shared.open(primary)
        } else {
            UIApplication.shared.open(config.appStoreWebURL)
        }
        #endif
    }

    // MARK: - Private

    private func apply(requiresUpdate: Bool, latestVersion: String?) {
        self.requiresUpdate = requiresUpdate
        self.latestAppStoreVersion = latestVersion
    }

    private func applyFailOpen() {
        apply(requiresUpdate: false, latestVersion: nil)
        // Cache the failure so we don't hammer the endpoint on retry.
        saveCache(CachedDecision(
            requiresUpdate: false,
            latestAppStoreVersion: nil,
            installedVersion: installedVersion,
            timestamp: Date().timeIntervalSince1970
        ))
    }

    private var cacheKey: String {
        "\(config.userDefaultsSuitePrefix)_cache"
    }

    private func loadCache() -> CachedDecision? {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(CachedDecision.self, from: data) else {
            return nil
        }
        // Invalidate cache on installed version change so a fresh post-update
        // launch never sees a stale `requiresUpdate=true`.
        guard decoded.installedVersion == installedVersion else {
            return nil
        }
        return decoded
    }

    private func saveCache(_ decision: CachedDecision) {
        if let data = try? JSONEncoder().encode(decision) {
            userDefaults.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Models

    private struct LookupResponse: Codable {
        let results: [Result]
        struct Result: Codable {
            let version: String
        }
    }

    struct CachedDecision: Codable {
        let requiresUpdate: Bool
        let latestAppStoreVersion: String?
        let installedVersion: String
        let timestamp: TimeInterval

        func isExpired(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince1970 - timestamp > ttl
        }
    }
}
