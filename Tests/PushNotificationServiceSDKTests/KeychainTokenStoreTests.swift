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

    func test_saveThenLoadRoundTrips() {
        let store = makeStore()
        defer { store.clear() } // each test mints its own service, but never cleaning up leaves a permanent orphaned keychain item behind on every CI run
        store.save("abc123")
        XCTAssertEqual(store.load(), "abc123")
    }

    func test_saveTwiceOverwrites() {
        let store = makeStore()
        defer { store.clear() }
        store.save("first")
        store.save("second")
        XCTAssertEqual(store.load(), "second")
    }

    func test_clearRemovesTheStoredToken() {
        let store = makeStore()
        store.save("abc123")
        store.clear()
        XCTAssertNil(store.load())
    }
}
