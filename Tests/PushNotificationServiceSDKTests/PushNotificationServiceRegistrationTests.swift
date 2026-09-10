import XCTest
@testable import PushNotificationServiceSDK
import PushNotificationServiceTestSupport

final class PushNotificationServiceRegistrationTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_didReceiveToken_registersHexEncodedTokenWithBundleId() async throws {
        var capturedBody: [String: Any] = [:]
        MockURLProtocol.requestHandler = { request in
            capturedBody = try! JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"deviceToken":"dt_1"}"#.utf8))
        }

        PushNotificationService.configureForTesting(
            siteId: "site-123", baseURL: URL(string: "https://api.pushnotificationservice.com")!,
            session: MockURLProtocol.makeSession(), tokenStore: KeychainTokenStore(service: "test.\(UUID())")
        )

        try await PushNotificationService.didReceiveToken(Data([0xAB, 0xCD]))

        XCTAssertEqual(capturedBody["token"] as? String, "abcd")
        XCTAssertNotNil(capturedBody["bundle_id"]) // Bundle.main.bundleIdentifier in the XCTest host
    }

    func test_didReceiveToken_secondCallSendsFirstTokenAsOldToken() async throws {
        var requestCount = 0
        var secondRequestBody: [String: Any] = [:]
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 2 {
                secondRequestBody = try! JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"deviceToken":"dt_1"}"#.utf8))
        }

        let tokenStore = KeychainTokenStore(service: "test.\(UUID())")
        PushNotificationService.configureForTesting(
            siteId: "site-123", baseURL: URL(string: "https://api.pushnotificationservice.com")!,
            session: MockURLProtocol.makeSession(), tokenStore: tokenStore
        )

        try await PushNotificationService.didReceiveToken(Data([0x01]))
        try await PushNotificationService.didReceiveToken(Data([0x02]))

        XCTAssertEqual(secondRequestBody["token"] as? String, "02")
        XCTAssertEqual(secondRequestBody["old_token"] as? String, "01")
    }

    func test_didReceiveToken_throwsNotConfiguredWithoutConfigure() async {
        PushNotificationService.resetForTesting()
        do {
            try await PushNotificationService.didReceiveToken(Data([0x01]))
            XCTFail("expected throw")
        } catch PushNotificationServiceError.notConfigured {
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_unregister_clearsPersistedToken() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        let tokenStore = KeychainTokenStore(service: "test.\(UUID())")
        tokenStore.save("existing")
        PushNotificationService.configureForTesting(
            siteId: "site-123", baseURL: URL(string: "https://api.pushnotificationservice.com")!,
            session: MockURLProtocol.makeSession(), tokenStore: tokenStore
        )

        try await PushNotificationService.unregister()

        XCTAssertNil(tokenStore.load())
    }

    func test_shortLocaleIdentifier_neverExceedsServerMax16Chars() {
        // StoreDeviceTokenRequest validates meta.locale with max:16. Locale.current.identifier
        // can carry keyword extensions (e.g. "en_US@calendar=japanese") well past that — this
        // guards the language+region-only shortening plus the hard-truncation backstop.
        let withExtension = Locale(identifier: "en_US@calendar=japanese;currency=JPY")
        XCTAssertLessThanOrEqual(PushNotificationService.shortLocaleIdentifier(withExtension).count, 16)
        XCTAssertEqual(PushNotificationService.shortLocaleIdentifier(withExtension), "en-US")

        let plain = Locale(identifier: "fr_FR")
        XCTAssertEqual(PushNotificationService.shortLocaleIdentifier(plain), "fr-FR")
    }

    func test_didReceiveToken_sameTokenTwiceOmitsOldToken() async throws {
        var capturedBodies: [[String: Any]] = []
        MockURLProtocol.requestHandler = { request in
            capturedBodies.append(try! JSONSerialization.jsonObject(with: request.httpBodyOrStream()) as! [String: Any])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"deviceToken":"dt_1"}"#.utf8))
        }

        PushNotificationService.configureForTesting(
            siteId: "site-123", baseURL: URL(string: "https://api.pushnotificationservice.com")!,
            session: MockURLProtocol.makeSession(), tokenStore: KeychainTokenStore(service: "test.\(UUID())")
        )

        try await PushNotificationService.didReceiveToken(Data([0x01]))
        try await PushNotificationService.didReceiveToken(Data([0x01])) // same token again — idempotent re-register

        XCTAssertNil(capturedBodies[1]["old_token"]) // oldToken == token, so it's correctly omitted, not re-sent as itself
    }

    func test_unregister_withNothingPersistedDoesNotCallTheApi() async throws {
        MockURLProtocol.requestHandler = { _ in XCTFail("should not call the API — nothing was ever registered"); fatalError() }

        PushNotificationService.configureForTesting(
            siteId: "site-123", baseURL: URL(string: "https://api.pushnotificationservice.com")!,
            session: MockURLProtocol.makeSession(), tokenStore: KeychainTokenStore(service: "test.\(UUID())")
        )

        try await PushNotificationService.unregister()
        // No expectation to wait on — absence of a request is the assertion.
    }
}

private extension URLRequest {
    func httpBodyOrStream() -> Data {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
