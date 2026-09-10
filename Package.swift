// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PushNotificationServiceSDK",
    // .macOS(.v12) does not raise the iOS floor (still .v15 below) — it's the
    // minimum needed for `swift test` to compile at all. `swift test` runs
    // against the host Mac, not an iOS destination, and HTTPClient.get uses
    // `URLSession.data(from:)`, whose async overload is @available(iOS 15,
    // macOS 12, ...). Without an explicit macOS platform here, SwiftPM falls
    // back to swift-tools-version 5.9's old default macOS deployment target
    // (well below 12), and that availability check fails to compile.
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "PushNotificationServiceSDK", targets: ["PushNotificationServiceSDK"]),
        .library(name: "PushNotificationServiceExtensionKit", targets: ["PushNotificationServiceExtensionKit"]),
    ],
    targets: [
        .target(name: "PushNotificationServiceCore"),
        .target(name: "PushNotificationServiceTestSupport", dependencies: ["PushNotificationServiceCore"]),
        .target(name: "PushNotificationServiceSDK", dependencies: ["PushNotificationServiceCore"]),
        .target(name: "PushNotificationServiceExtensionKit", dependencies: ["PushNotificationServiceCore"]),
        .testTarget(name: "PushNotificationServiceCoreTests", dependencies: ["PushNotificationServiceCore", "PushNotificationServiceTestSupport"]),
        .testTarget(name: "PushNotificationServiceSDKTests", dependencies: ["PushNotificationServiceSDK", "PushNotificationServiceTestSupport"]),
        .testTarget(name: "PushNotificationServiceExtensionKitTests", dependencies: ["PushNotificationServiceExtensionKit", "PushNotificationServiceTestSupport"]),
    ]
)
