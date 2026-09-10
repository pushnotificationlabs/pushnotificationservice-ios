import Foundation
import PushNotificationServiceCore // Data.hexEncodedString() — a Package.swift
// target dependency only makes a module importable; every file that actually
// uses its symbols (including extension members like this one) needs its own
// import statement, or the whole target fails to build.
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

public enum PushNotificationService {
    private struct Configuration {
        let siteId: String
        let api: DeviceTokenAPI
        let tokenStore: TokenStoring
    }

    private static var configuration: Configuration?

    /// Optional override for a tapped notification's tracking URL — if set,
    /// the SDK calls this instead of opening the URL itself (e.g. to present
    /// an in-app browser). If unset, the default is to open it via the OS.
    public static var onNotificationTapped: ((URL) -> Void)?

    /// Configures the SDK against your site. Call once, e.g. in
    /// `application(_:didFinishLaunchingWithOptions:)`.
    public static func configure(siteId: String) {
        configureForTesting(
            siteId: siteId,
            baseURL: URL(string: "https://api.pushnotificationservice.com")!,
            session: .shared,
            tokenStore: KeychainTokenStore()
        )
    }

    /// Test-only seam — not part of the public product surface described in
    /// the spec, but `internal` visibility would hide it from `@testable`
    /// imports across module boundaries the same way `private` would, so
    /// this stays a plainly-named, documented internal entry point.
    static func configureForTesting(siteId: String, baseURL: URL, session: URLSession, tokenStore: TokenStoring) {
        configuration = Configuration(siteId: siteId, api: DeviceTokenAPI(baseURL: baseURL, session: session), tokenStore: tokenStore)
    }

    static func resetForTesting() {
        configuration = nil
        onNotificationTapped = nil
        urlOpenerForTesting = nil
        httpSessionForTesting = nil
    }

    /// Call from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Automatically supplies the last-registered token as `old_token` and
    /// persists the new one on success.
    public static func didReceiveToken(_ deviceToken: Data) async throws {
        guard let configuration else { throw PushNotificationServiceError.notConfigured }

        let token = deviceToken.hexEncodedString()
        let oldToken = configuration.tokenStore.load()
        let meta = currentMeta()

        _ = try await configuration.api.register(
            siteId: configuration.siteId, platform: "ios", token: token,
            oldToken: oldToken == token ? nil : oldToken,
            bundleId: Bundle.main.bundleIdentifier, meta: meta
        )

        configuration.tokenStore.save(token)
    }

    /// e.g. on logout / opt-out.
    public static func unregister() async throws {
        guard let configuration else { throw PushNotificationServiceError.notConfigured }
        guard let token = configuration.tokenStore.load() else { return }

        try await configuration.api.unregister(siteId: configuration.siteId, platform: "ios", token: token)
        configuration.tokenStore.clear()
    }

    private static func currentMeta() -> [String: String] {
        var meta: [String: String] = [:]
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            meta["app_version"] = version
        }
        #if canImport(UIKit)
        meta["os_version"] = UIDevice.current.systemVersion
        #endif
        meta["locale"] = shortLocaleIdentifier()
        return meta
    }

    /// `StoreDeviceTokenRequest` caps `meta.locale` at 16 chars. `Locale.current.identifier`
    /// is the wrong source for this: it's an ICU-style identifier that can carry keyword
    /// extensions (e.g. `en_US@calendar=japanese`) well past that limit. Prefer the plain
    /// language+region form (e.g. `en-US`), which is always short; the deprecated-in-later-OS
    /// `languageCode`/`regionCode` accessors are used deliberately since the min target here
    /// is iOS 15, before `Locale.Language`/`identifier(.bcp47)` existed. A hard truncation is
    /// kept as a backstop so a future locale format quirk can never turn into a 422.
    static func shortLocaleIdentifier(_ locale: Locale = .current) -> String {
        let parts = [locale.languageCode, locale.regionCode].compactMap { $0 }
        let short = parts.isEmpty ? locale.identifier : parts.joined(separator: "-")
        return String(short.prefix(16))
    }
}

extension PushNotificationService {
    /// Injectable for tests; production default is `URLSession.shared`.
    static var httpSessionForTesting: URLSession?
    /// Injectable for tests; production default opens via `UIApplication`.
    static var urlOpenerForTesting: ((URL) -> Void)?

    /// Call from `UNUserNotificationCenterDelegate`'s
    /// `userNotificationCenter(_:willPresent:withCompletionHandler:)`.
    public static func willPresent(_ notification: UNNotification) async -> UNNotificationPresentationOptions {
        handleDisplay(userInfo: notification.request.content.userInfo)
        return [.banner, .sound, .list]
    }

    /// Call from `UNUserNotificationCenterDelegate`'s
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    public static func didReceive(_ response: UNNotificationResponse) async {
        await handleTap(userInfo: response.notification.request.content.userInfo)
    }

    /// Pings the displayedUrl receipt. Best-effort and fire-and-forget by
    /// design: a failed/slow ping must never delay or block the notification
    /// from showing. Skips entirely if the Notification Service Extension
    /// already pinged successfully for this notification (see
    /// PushNotificationServiceExtension.pingDisplayedUrl) — otherwise a
    /// foregrounded notification (NSE runs, then willPresent also runs)
    /// gets double-counted, and the backend's displayedUrl receipt is
    /// campaign-scoped with no per-device component, so it can't dedupe.
    static func handleDisplay(userInfo: [AnyHashable: Any]) {
        guard userInfo["_pnsDisplayPinged"] as? Bool != true else { return }
        guard let urlString = userInfo["displayedUrl"] as? String, let url = URL(string: urlString) else { return }
        let session = httpSessionForTesting ?? .shared
        Task { _ = try? await HTTPClient.get(url, session: session) }
    }

    /// The `url` field is always a signed click-counting redirect, never the
    /// real destination (see spec "Tap handling") — it is opened verbatim,
    /// never resolved/followed client-side.
    static func handleTap(userInfo: [AnyHashable: Any]) async {
        guard let urlString = userInfo["url"] as? String, let url = URL(string: urlString) else { return }

        if let handler = onNotificationTapped {
            handler(url)
            return
        }
        if let opener = urlOpenerForTesting {
            opener(url)
            return
        }
        #if canImport(UIKit)
        _ = await UIApplication.shared.open(url)
        #endif
    }
}
