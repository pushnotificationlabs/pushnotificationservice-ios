import XCTest
@testable import PushNotificationServiceCore

final class HexEncodingTests: XCTestCase {
    func test_hexEncodedString_encodesKnownBytes() {
        XCTAssertEqual(Data([0xAB, 0xCD, 0x01, 0x23]).hexEncodedString(), "abcd0123")
    }

    func test_hexEncodedString_isLowercase() {
        XCTAssertEqual(Data([0xFF, 0x0A]).hexEncodedString(), "ff0a")
    }

    func test_hexEncodedString_emptyData() {
        XCTAssertEqual(Data().hexEncodedString(), "")
    }
}
