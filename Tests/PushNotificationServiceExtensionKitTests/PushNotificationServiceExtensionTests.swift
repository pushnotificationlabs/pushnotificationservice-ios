import XCTest
import UserNotifications
@testable import PushNotificationServiceExtensionKit
import PushNotificationServiceTestSupport

final class PushNotificationServiceExtensionTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_process_pingsDisplayedUrl() async {
        var pinged = false
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/d/campaign-1" { pinged = true }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        let content = UNMutableNotificationContent()
        content.userInfo = ["displayedUrl": "https://api.pushnotificationservice.com/d/campaign-1"]

        _ = await PushNotificationServiceExtension.process(userInfo: content.userInfo, content: content, session: MockURLProtocol.makeSession())

        XCTAssertTrue(pinged)
    }

    // A real, decodable 1x1-pixel red JPEG (633 bytes, base64-encoded) — not
    // an arbitrary 4-byte SOI/EOI pair. UNNotificationAttachment(identifier:url:)
    // is undocumented on whether it validates image structure at creation time
    // vs. only at render time (UNError does have an .attachmentCorrupt case,
    // suggesting it might); using genuinely valid bytes makes this test's
    // pass/fail independent of that open question either way.
    static let tinyValidJPEGBase64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDi6KKK+ZP3E//Z"

    func test_process_attachesDownloadedImage() async {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/image.jpg" {
                let jpegData = Data(base64Encoded: Self.tinyValidJPEGBase64)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!, jpegData)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        let content = UNMutableNotificationContent()
        content.userInfo = ["image": "https://api.pushnotificationservice.com/image.jpg"]

        let result = await PushNotificationServiceExtension.process(userInfo: content.userInfo, content: content, session: MockURLProtocol.makeSession())

        XCTAssertEqual(result.attachments.count, 1)
    }

    func test_process_noImageOrDisplayedUrlReturnsContentUnchanged() async {
        let content = UNMutableNotificationContent()
        content.title = "Sale"

        let result = await PushNotificationServiceExtension.process(userInfo: [:], content: content, session: MockURLProtocol.makeSession())

        XCTAssertEqual(result.title, "Sale")
        XCTAssertEqual(result.attachments.count, 0)
    }

    func test_process_imageDownloadFailureLeavesContentUsable() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        let content = UNMutableNotificationContent()
        content.userInfo = ["image": "https://api.pushnotificationservice.com/image.jpg"]

        let result = await PushNotificationServiceExtension.process(userInfo: content.userInfo, content: content, session: MockURLProtocol.makeSession())

        // A failed image download must not lose the notification entirely.
        XCTAssertEqual(result.attachments.count, 0)
    }

    func test_process_stampsDisplayPingedFlagOnSuccessfulPing() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        let content = UNMutableNotificationContent()
        content.userInfo = ["displayedUrl": "https://api.pushnotificationservice.com/d/campaign-1"]

        let result = await PushNotificationServiceExtension.process(userInfo: content.userInfo, content: content, session: MockURLProtocol.makeSession())

        XCTAssertEqual(result.userInfo["_pnsDisplayPinged"] as? Bool, true)
    }

    func test_process_doesNotStampFlagWhenPingFails() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        let content = UNMutableNotificationContent()
        content.userInfo = ["displayedUrl": "https://api.pushnotificationservice.com/d/campaign-1"]

        let result = await PushNotificationServiceExtension.process(userInfo: content.userInfo, content: content, session: MockURLProtocol.makeSession())

        XCTAssertNil(result.userInfo["_pnsDisplayPinged"])
    }
}
