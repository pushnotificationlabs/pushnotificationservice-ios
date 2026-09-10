import XCTest
@testable import PushNotificationServiceCore
import PushNotificationServiceTestSupport

final class HTTPClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_get_returnsBodyOn200() async throws {
        let url = URL(string: "https://api.pushnotificationservice.com/d/abc")!
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }
        let data = try await HTTPClient.get(url, session: MockURLProtocol.makeSession())
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }

    func test_get_throwsOnNon2xx() async {
        let url = URL(string: "https://api.pushnotificationservice.com/d/abc")!
        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await HTTPClient.get(url, session: MockURLProtocol.makeSession())
            XCTFail("expected throw")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        }
    }
}
