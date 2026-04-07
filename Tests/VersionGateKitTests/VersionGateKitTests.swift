import XCTest
@testable import VersionGateKit

@MainActor
final class VersionGateKitTests: XCTestCase {

    // MARK: - SemanticVersion

    func testSemanticVersionPatchOrdering() {
        XCTAssertTrue(SemanticVersion("1.2.10")! > SemanticVersion("1.2.9")!)
    }

    func testSemanticVersionMinorOrdering() {
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.99")!)
    }

    func testSemanticVersionMajorOrdering() {
        XCTAssertTrue(SemanticVersion("2.0")! > SemanticVersion("1.99.99")!)
    }

    func testSemanticVersionEquality() {
        XCTAssertEqual(SemanticVersion("1.2.0"), SemanticVersion("1.2.0.0"))
        XCTAssertEqual(SemanticVersion("1.2"), SemanticVersion("1.2.0"))
    }

    func testSemanticVersionInvalidStrings() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion("1.2.x"))
        XCTAssertNil(SemanticVersion("1.2.3.4.5"))
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suiteName = "version-gate-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeManager(
        installedVersion: String = "1.0.0",
        userDefaults: UserDefaults? = nil,
        session: URLSession = .shared,
        suitePrefix: String = "versiongatekit",
        minimumVersionProvider: (() -> String?)? = nil
    ) -> VersionGateManager {
        let defaults = userDefaults ?? makeDefaults()
        let manager = VersionGateManager(session: session, userDefaults: defaults)
        manager.configure(VersionGateKitConfig(
            bundleId: "test.bundle.id",
            appStoreId: "1234567890",
            installedVersion: installedVersion,
            userDefaultsSuitePrefix: suitePrefix,
            minimumVersionProvider: minimumVersionProvider
        ))
        return manager
    }

    // MARK: - Cache behavior

    func testCacheHitShortCircuitsNetwork() async {
        let defaults = makeDefaults()
        let suitePrefix = "vgk_cache_hit"
        // Pre-seed cache with a recent decision saying update is required.
        let cached = VersionGateManager.CachedDecision(
            requiresUpdate: true,
            latestAppStoreVersion: "5.0.0",
            installedVersion: "1.0.0",
            timestamp: Date().timeIntervalSince1970
        )
        let data = try! JSONEncoder().encode(cached)
        defaults.set(data, forKey: "\(suitePrefix)_cache")

        let manager = makeManager(
            installedVersion: "1.0.0",
            userDefaults: defaults,
            session: .shared,
            suitePrefix: suitePrefix
        )

        await manager.checkIfNeeded()

        XCTAssertTrue(manager.requiresUpdate)
        XCTAssertEqual(manager.latestAppStoreVersion, "5.0.0")
    }

    func testCacheInvalidatedByInstalledVersionChange() async {
        let defaults = makeDefaults()
        let suitePrefix = "vgk_cache_invalidated"
        // Cache says update required for installed 1.0.0
        let cached = VersionGateManager.CachedDecision(
            requiresUpdate: true,
            latestAppStoreVersion: "5.0.0",
            installedVersion: "1.0.0",
            timestamp: Date().timeIntervalSince1970
        )
        defaults.set(try! JSONEncoder().encode(cached), forKey: "\(suitePrefix)_cache")

        // We're now on 5.0.0; the cached decision must be ignored. Use a
        // failing session so the network path fail-opens.
        let failingConfig = URLSessionConfiguration.ephemeral
        failingConfig.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: "test", code: -1)
        }
        let failingSession = URLSession(configuration: failingConfig)
        let manager = makeManager(
            installedVersion: "5.0.0",
            userDefaults: defaults,
            session: failingSession,
            suitePrefix: suitePrefix
        )

        await manager.checkIfNeeded()
        XCTAssertFalse(manager.requiresUpdate)
        MockURLProtocol.requestHandler = nil
    }

    func testExpiredCacheIsExpired() {
        let stale = VersionGateManager.CachedDecision(
            requiresUpdate: true,
            latestAppStoreVersion: "5.0.0",
            installedVersion: "1.0.0",
            timestamp: Date().timeIntervalSince1970 - (7 * 3600)
        )
        XCTAssertTrue(stale.isExpired(ttl: 6 * 3600))

        let fresh = VersionGateManager.CachedDecision(
            requiresUpdate: true,
            latestAppStoreVersion: "5.0.0",
            installedVersion: "1.0.0",
            timestamp: Date().timeIntervalSince1970
        )
        XCTAssertFalse(fresh.isExpired(ttl: 6 * 3600))
    }

    // MARK: - Decision matrix (pure semantic comparison)

    func testInstalledOlderThanStoreRequiresUpdate() {
        let installed = SemanticVersion("1.0.0")!
        let store = SemanticVersion("1.1.0")!
        XCTAssertTrue(installed < store)
    }

    func testInstalledEqualToStoreDoesNotRequireUpdate() {
        let installed = SemanticVersion("1.1.0")!
        let store = SemanticVersion("1.1.0")!
        XCTAssertFalse(installed < store)
    }

    func testInstalledNewerThanStoreDoesNotRequireUpdate() {
        let installed = SemanticVersion("2.0.0")!
        let store = SemanticVersion("1.1.0")!
        XCTAssertFalse(installed < store)
    }

    func testConfigFloorOverridesStoreVersion() {
        let store = SemanticVersion("1.0.0")!
        let configFloor = SemanticVersion("2.0.0")!
        let required = max(store, configFloor)
        XCTAssertEqual(required, configFloor)

        let installed = SemanticVersion("1.5.0")!
        XCTAssertTrue(installed < required)
    }

    // MARK: - New tests for the package boundary

    func testConfigureUpdatesInstalledVersion() {
        let manager = makeManager(installedVersion: "2.0.0")
        XCTAssertEqual(manager.installedVersion, "2.0.0")
    }

    func testCacheKeyHonorsSuitePrefix() async {
        let defaults = makeDefaults()
        let failingConfig = URLSessionConfiguration.ephemeral
        failingConfig.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: "test", code: -1)
        }
        let failingSession = URLSession(configuration: failingConfig)

        let manager = makeManager(
            installedVersion: "1.0.0",
            userDefaults: defaults,
            session: failingSession,
            suitePrefix: "test_prefix"
        )

        await manager.checkIfNeeded()

        XCTAssertNotNil(defaults.data(forKey: "test_prefix_cache"))
        XCTAssertNil(defaults.data(forKey: "versiongatekit_cache"))
        MockURLProtocol.requestHandler = nil
    }

    func testNetworkSuccessPathRequiresUpdate() async {
        let defaults = makeDefaults()
        let mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockURLProtocol.self]

        MockURLProtocol.requestHandler = { request in
            let json = #"{"results":[{"version":"9.9.9"}]}"#
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let session = URLSession(configuration: mockConfig)
        let manager = makeManager(
            installedVersion: "1.0.0",
            userDefaults: defaults,
            session: session,
            suitePrefix: "vgk_network_success"
        )

        await manager.checkIfNeeded()

        XCTAssertTrue(manager.requiresUpdate)
        XCTAssertEqual(manager.latestAppStoreVersion, "9.9.9")
        MockURLProtocol.requestHandler = nil
    }

    func testUnconfiguredManagerIsNoOp() async {
        let manager = VersionGateManager(session: .shared, userDefaults: makeDefaults())
        // Note: not calling configure(); bundleId is empty.
        await manager.checkIfNeeded()
        XCTAssertFalse(manager.requiresUpdate)
        XCTAssertNil(manager.latestAppStoreVersion)
    }

    // MARK: - Enforcement mode defaults

    func testEnforcementDefaultsToRequired() {
        let config = VersionGateKitConfig(bundleId: "x", appStoreId: "y")
        switch config.enforcement {
        case .required:
            break
        case .reminder, .aggressive:
            XCTFail("Expected default enforcement to be .required")
        }
    }

    func testReminderSettingsDefaults() {
        let settings = VersionGateReminderSettings()
        XCTAssertEqual(settings.snoozeDuration, 24 * 3600)
        XCTAssertEqual(settings.dismissButtonLabel, "Later")
    }

    func testAggressiveSettingsDefaults() {
        let settings = VersionGateAggressiveSettings()
        XCTAssertEqual(settings.dismissDelay, 3.0)
        XCTAssertEqual(settings.dismissButtonLabel, "Later")
    }

    // MARK: - Enforcement helpers

    private func mockSession(returning version: String) -> URLSession {
        let mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { request in
            let json = "{\"results\":[{\"version\":\"\(version)\"}]}"
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
        return URLSession(configuration: mockConfig)
    }

    private func makeManagerWithEnforcement(
        enforcement: VersionGateEnforcement,
        installedVersion: String = "1.0.0",
        userDefaults: UserDefaults,
        session: URLSession,
        suitePrefix: String
    ) -> VersionGateManager {
        let manager = VersionGateManager(session: session, userDefaults: userDefaults)
        manager.configure(VersionGateKitConfig(
            bundleId: "test.bundle.id",
            appStoreId: "1234567890",
            installedVersion: installedVersion,
            userDefaultsSuitePrefix: suitePrefix,
            enforcement: enforcement
        ))
        return manager
    }

    // MARK: - dismiss() semantics

    func testDismissIsNoOpUnderRequired() async {
        let defaults = makeDefaults()
        let session = mockSession(returning: "9.9.9")
        let manager = makeManagerWithEnforcement(
            enforcement: .required,
            userDefaults: defaults,
            session: session,
            suitePrefix: "vgk_dismiss_required"
        )
        await manager.checkIfNeeded()
        XCTAssertTrue(manager.requiresUpdate)
        manager.dismiss()
        XCTAssertFalse(manager.isDismissed)
        MockURLProtocol.requestHandler = nil
    }

    func testDismissUnderReminderSetsFlagAndPersists() async {
        let defaults = makeDefaults()
        let session = mockSession(returning: "9.9.9")
        let suitePrefix = "vgk_dismiss_reminder"
        let manager = makeManagerWithEnforcement(
            enforcement: .reminder(.init(snoozeDuration: 3600)),
            userDefaults: defaults,
            session: session,
            suitePrefix: suitePrefix
        )
        await manager.checkIfNeeded()
        XCTAssertTrue(manager.requiresUpdate)
        manager.dismiss()
        XCTAssertTrue(manager.isDismissed)

        // Fresh manager pointed at the same defaults — should restore snooze.
        let manager2 = makeManagerWithEnforcement(
            enforcement: .reminder(.init(snoozeDuration: 3600)),
            userDefaults: defaults,
            session: session,
            suitePrefix: suitePrefix
        )
        await manager2.checkIfNeeded()
        XCTAssertTrue(manager2.requiresUpdate)
        XCTAssertTrue(manager2.isDismissed)
        MockURLProtocol.requestHandler = nil
    }

    func testReminderSnoozeExpiresAfterTTL() async {
        let defaults = makeDefaults()
        let suitePrefix = "vgk_snooze_expired"
        // Pre-seed a stale dismissal for version 5.0.0.
        let stale = VersionGateManager.CachedDecision(
            requiresUpdate: true,
            latestAppStoreVersion: "5.0.0",
            installedVersion: "1.0.0",
            timestamp: Date().timeIntervalSince1970,
            dismissedAt: Date().timeIntervalSince1970 - 7200,
            dismissedForVersion: "5.0.0"
        )
        defaults.set(try! JSONEncoder().encode(stale), forKey: "\(suitePrefix)_cache")

        let manager = makeManagerWithEnforcement(
            enforcement: .reminder(.init(snoozeDuration: 3600)),
            userDefaults: defaults,
            session: .shared,
            suitePrefix: suitePrefix
        )
        await manager.checkIfNeeded()
        XCTAssertTrue(manager.requiresUpdate)
        XCTAssertFalse(manager.isDismissed)
    }

    func testReminderSnoozeInvalidatedByNewerStoreVersion() async {
        let defaults = makeDefaults()
        let suitePrefix = "vgk_snooze_newer_version"
        // Pre-seed dismissal for version 5.0.0 but network returns 9.9.9.
        let seeded = VersionGateManager.CachedDecision(
            requiresUpdate: true,
            latestAppStoreVersion: "5.0.0",
            installedVersion: "1.0.0",
            timestamp: Date().timeIntervalSince1970 - (7 * 3600),  // forces network path
            dismissedAt: Date().timeIntervalSince1970,
            dismissedForVersion: "5.0.0"
        )
        defaults.set(try! JSONEncoder().encode(seeded), forKey: "\(suitePrefix)_cache")

        let session = mockSession(returning: "9.9.9")
        let manager = makeManagerWithEnforcement(
            enforcement: .reminder(.init(snoozeDuration: 24 * 3600)),
            userDefaults: defaults,
            session: session,
            suitePrefix: suitePrefix
        )
        await manager.checkIfNeeded()
        XCTAssertTrue(manager.requiresUpdate)
        XCTAssertEqual(manager.latestAppStoreVersion, "9.9.9")
        XCTAssertFalse(manager.isDismissed)
        MockURLProtocol.requestHandler = nil
    }

    func testDismissUnderAggressiveDoesNotPersist() async {
        let defaults = makeDefaults()
        let session = mockSession(returning: "9.9.9")
        let suitePrefix = "vgk_dismiss_aggressive"
        let manager = makeManagerWithEnforcement(
            enforcement: .aggressive(.init(dismissDelay: 0)),
            userDefaults: defaults,
            session: session,
            suitePrefix: suitePrefix
        )
        await manager.checkIfNeeded()
        XCTAssertTrue(manager.requiresUpdate)
        manager.dismiss()
        XCTAssertTrue(manager.isDismissed)

        let manager2 = makeManagerWithEnforcement(
            enforcement: .aggressive(.init(dismissDelay: 0)),
            userDefaults: defaults,
            session: session,
            suitePrefix: suitePrefix
        )
        await manager2.checkIfNeeded()
        XCTAssertTrue(manager2.requiresUpdate)
        XCTAssertFalse(manager2.isDismissed)
        MockURLProtocol.requestHandler = nil
    }

    // MARK: - Backwards-compat regression

    func testExistingInitSignatureStillCompiles() {
        _ = VersionGateKitConfig(bundleId: "x", appStoreId: "y")
        _ = VersionGateKitConfig(
            bundleId: "x",
            appStoreId: "y",
            installedVersion: "1.0.0",
            cacheTTL: 60,
            userDefaultsSuitePrefix: "p",
            minimumVersionProvider: { nil }
        )
    }
}
