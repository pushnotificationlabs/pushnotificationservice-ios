import XCTest
@testable import PushNotificationServiceSDK
import PushNotificationServiceTestSupport

final class NotificationHandlingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        PushNotificationService.onNotificationTapped = nil
        PushNotificationService.urlOpenerForTesting = nil
        PushNotificationService.httpSessionForTesting = nil
        super.tearDown()
    }

    func test_handleDisplay_pingsDisplayedUrl() {
        let expectation = expectation(description: "ping fired")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/d/campaign-1")
            expectation.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        PushNotificationService.httpSessionForTesting = MockURLProtocol.makeSession()

        PushNotificationService.handleDisplay(userInfo: ["displayedUrl": "https://api.pushnotificationservice.com/d/campaign-1"])

        wait(for: [expectation], timeout: 1)
    }

    func test_handleDisplay_missingDisplayedUrlDoesNothing() {
        MockURLProtocol.requestHandler = { _ in XCTFail("should not fire a request"); fatalError() }
        PushNotificationService.httpSessionForTesting = MockURLProtocol.makeSession()
        PushNotificationService.handleDisplay(userInfo: [:])
        // No expectation to wait on — absence of a crash/call is the assertion.
    }

    func test_handleDisplay_skipsPingWhenAlreadyPingedByExtension() {
        MockURLProtocol.requestHandler = { _ in XCTFail("should not fire a request — NSE already pinged"); fatalError() }
        PushNotificationService.httpSessionForTesting = MockURLProtocol.makeSession()

        PushNotificationService.handleDisplay(userInfo: [
            "displayedUrl": "https://api.pushnotificationservice.com/d/campaign-1",
            "_pnsDisplayPinged": true,
        ])
        // No expectation to wait on — absence of a request is the assertion.
    }

    func test_handleTap_callsCustomHandlerWithTrackingUrlWhenSet() async {
        var received: URL?
        PushNotificationService.onNotificationTapped = { received = $0 }

        await PushNotificationService.handleTap(userInfo: ["url": "https://api.pushnotificationservice.com/c/campaign-1"])

        XCTAssertEqual(received?.absoluteString, "https://api.pushnotificationservice.com/c/campaign-1")
    }

    func test_handleTap_usesDefaultOpenerWhenNoCustomHandlerSet() async {
        var opened: URL?
        PushNotificationService.urlOpenerForTesting = { opened = $0 }

        await PushNotificationService.handleTap(userInfo: ["url": "https://api.pushnotificationservice.com/c/campaign-1"])

        XCTAssertEqual(opened?.absoluteString, "https://api.pushnotificationservice.com/c/campaign-1")
    }

    func test_handleTap_missingUrlDoesNothing() async {
        PushNotificationService.urlOpenerForTesting = { _ in XCTFail("should not open anything") }
        await PushNotificationService.handleTap(userInfo: [:])
    }
}
