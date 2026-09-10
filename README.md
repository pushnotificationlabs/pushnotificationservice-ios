# PushNotificationService iOS SDK

[![Test](https://github.com/pushnotificationlabs/pushnotificationservice-ios/actions/workflows/test.yml/badge.svg)](https://github.com/pushnotificationlabs/pushnotificationservice-ios/actions/workflows/test.yml)

Swift Package wrapping PushNotificationService.com's native device-token
REST API. Min target: iOS 15. Zero third-party dependencies.

## Install

Xcode → File → Add Package Dependencies → `https://github.com/pushnotificationlabs/pushnotificationservice-ios`

## Register for push

Requires the Xcode **Push Notifications** capability enabled on your app
target (Signing & Capabilities → + Capability → Push Notifications) — this
provisions the `aps-environment` entitlement, without which
`registerForRemoteNotifications()` fails silently.

```swift
import UIKit
import PushNotificationServiceSDK
import UserNotifications

// AppDelegate.swift
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        PushNotificationService.configure(siteId: "YOUR_SITE_ID")
        UNUserNotificationCenter.current().delegate = self

        Task {
            // Without this, registerForRemoteNotifications() below still
            // produces a device token, but the app is never authorized to
            // actually display anything — silently.
            let granted = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted == true {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { try? await PushNotificationService.didReceiveToken(deviceToken) }
    }

    // UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await PushNotificationService.willPresent(notification)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await PushNotificationService.didReceive(response)
    }
}
```

## Unregister (e.g. on logout)

Call from an async context (e.g. a button action's `Task { }`, or an
existing `async` function):

```swift
Task {
    try? await PushNotificationService.unregister()
}
```

## Error handling

`didReceiveToken(_:)` and `unregister()` both throw `PushNotificationServiceError`:

```swift
public enum PushNotificationServiceError: Error, Equatable {
    case notConfigured        // called before configure(siteId:)
    case serverError(statusCode: Int)
    case invalidResponse      // 2xx response wasn't the expected shape
    case transport             // no connectivity, timeout, etc.
}
```

The samples above use `try?` for brevity; switch on the error if you want
to react differently (e.g. retry `.transport` failures, but not
`.serverError`).

## Rich images + reliable display receipts (recommended)

The backend attaches an image to some notifications and expects a receipt
ping when a notification is actually shown — both require a small
Notification Service Extension in your app:

1. Xcode → File → New → Target → **Notification Service Extension**.
2. Add the `PushNotificationServiceExtensionKit` product to that new target.
3. Replace the generated `NotificationService.swift` with:

```swift
import PushNotificationServiceExtensionKit

final class NotificationService: PushNotificationServiceExtension {}
```

This is **best-effort**: iOS can skip service extensions under memory
pressure or Low Power Mode, and they run under a hard time budget. Without
this extension, notifications still display and are still tappable — you
just won't get the image attachment or a receipt ping while the app is
backgrounded.

## Custom tap handling

By default, tapping a notification opens its (tracking) URL via the OS. To
intercept instead (e.g. present an in-app browser sheet):

```swift
PushNotificationService.onNotificationTapped = { url in
    // your own routing/presentation
}
```

`onNotificationTapped` is invoked from a background context, not the main
thread — if your handler does any UI work (presenting a sheet, updating a
view), hop to the main actor yourself:

```swift
PushNotificationService.onNotificationTapped = { url in
    Task { @MainActor in
        // present your in-app browser sheet with `url` here
    }
}
```

## License

MIT
