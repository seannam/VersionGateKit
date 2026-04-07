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
}
