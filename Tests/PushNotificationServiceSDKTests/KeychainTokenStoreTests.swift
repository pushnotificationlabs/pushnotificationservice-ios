import XCTest
@testable import PushNotificationServiceSDK

final class KeychainTokenStoreTests: XCTestCase {
    // Unique service per test run so parallel/CI runs never collide.
    func makeStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "com.pushnotificationservice.sdk.test.\(UUID().uuidString)")
    }

    func test_loadReturnsNilWhenNothingSaved() {
        XCTAssertNil(makeStore().load())
    }

    func test_saveThenLoadRoundTrips() throws {
        try skipIfHostless()
        let store = makeStore()
        defer { store.clear() } // each test mints its own service, but never cleaning up leaves a permanent orphaned keychain item behind on every CI run
        store.save("abc123")
        XCTAssertEqual(store.load(), "abc123")
    }

    func test_saveTwiceOverwrites() throws {
        try skipIfHostless()
        let store = makeStore()
        defer { store.clear() }
        store.save("first")
        store.save("second")
        XCTAssertEqual(store.load(), "second")
    }

    func test_clearRemovesTheStoredToken() throws {
        try skipIfHostless()
        let store = makeStore()
        store.save("abc123")
        store.clear()
        XCTAssertNil(store.load())
    }

    // A raw SPM package (no wrapping .xcodeproj/.app target) produces a
    // hostless xctest bundle: no Info.plist-backed app identity, so it's in
    // no Keychain access group, and SecItemAdd/SecItemUpdate always fail
    // with errSecMissingEntitlement (-34018) — confirmed via real CI
    // (GitHub Actions macOS runner) on 2026-09-10; CODE_SIGNING_ALLOWED=NO
    // does NOT work around it (that flag addresses a signature check, not
    // the missing entitlement/access-group). There's no environment
    // variable for "am I hosted" — the save/load path itself is the only
    // detector: attempt a real round trip against a throwaway keychain item
    // and skip if it can't even persist one byte, rather than hardcoding a
    // check against Bundle.main (which is non-nil here regardless — it's
    // just the xctest runner's own bundle id, not evidence of a host app).
    private func skipIfHostless() throws {
        let probe = KeychainTokenStore(service: "com.pushnotificationservice.sdk.hostcheck.\(UUID().uuidString)")
        probe.save("x")
        let persisted = probe.load() != nil
        probe.clear()
        try XCTSkipUnless(persisted, "no Keychain access group in this hostless test bundle — see KeychainTokenStore doc comment above")
    }
}
