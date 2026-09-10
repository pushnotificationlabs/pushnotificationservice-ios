import XCTest
@testable import PushNotificationServiceSDK
import PushNotificationServiceTestSupport

final class DeviceTokenAPITests: XCTestCase {
    let baseURL = URL(string: "https://api.pushnotificationservice.com")!

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_register_postsToCorrectPathWithExpectedBody() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"deviceToken":"dt_abc123"}"#.utf8))
        }

        let api = DeviceTokenAPI(baseURL: baseURL, session: MockURLProtocol.makeSession())
        let id = try await api.register(
            siteId: "site-123", platform: "ios", token: "abcd", oldToken: "old-token",
            bundleId: "com.example.app", meta: ["app_version": "1.0", "os_version": "17.0", "locale": "en_US"]
        )

        XCTAssertEqual(id, "dt_abc123")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.pushnotificationservice.com/v1/sites/site-123/device-tokens")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        // The one header this plan already had to re-add once (ported from
        // the Android review, before Task 1 was even dispatched) — assert
        // it directly so a future refactor of post() can't silently drop it.
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(capturedRequest?.httpBodyStreamData())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["token"] as? String, "abcd")
        XCTAssertEqual(json["old_token"] as? String, "old-token")
        XCTAssertEqual(json["bundle_id"] as? String, "com.example.app")
        let meta = try XCTUnwrap(json["meta"] as? [String: String])
        XCTAssertEqual(meta["app_version"], "1.0")
    }

    func test_register_omitsOldTokenAndBundleIdWhenNil() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"deviceToken":"dt_abc123"}"#.utf8))
        }

        let api = DeviceTokenAPI(baseURL: baseURL, session: MockURLProtocol.makeSession())
        _ = try await api.register(siteId: "site-123", platform: "ios", token: "abcd", oldToken: nil, bundleId: nil, meta: [:])

        let body = try XCTUnwrap(capturedRequest?.httpBodyStreamData())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["old_token"])
        XCTAssertNil(json["bundle_id"])
    }

    func test_register_throwsServerErrorOnNon2xx() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!, Data())
        }
        let api = DeviceTokenAPI(baseURL: baseURL, session: MockURLProtocol.makeSession())
        do {
            _ = try await api.register(siteId: "site-123", platform: "ios", token: "abcd", oldToken: nil, bundleId: nil, meta: [:])
            XCTFail("expected throw")
        } catch PushNotificationServiceError.serverError(let statusCode) {
            XCTAssertEqual(statusCode, 422)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_unregister_postsToUnregisterPath() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        let api = DeviceTokenAPI(baseURL: baseURL, session: MockURLProtocol.makeSession())
        try await api.unregister(siteId: "site-123", platform: "ios", token: "abcd")

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.pushnotificationservice.com/v1/sites/site-123/device-tokens/unregister")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
    }
}

private extension URLRequest {
    /// `MockURLProtocol` sees the request after `httpBody` may have been
    /// moved to `httpBodyStream` by URLSession internals; read whichever is set.
    func httpBodyStreamData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
