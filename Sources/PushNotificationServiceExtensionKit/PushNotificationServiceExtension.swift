import UserNotifications
import PushNotificationServiceCore

/// Drop this into your app's own Notification Service Extension target
/// (Xcode → File → New → Target → Notification Service Extension), then
/// subclass it:
///
/// ```swift
/// import PushNotificationServiceExtensionKit
///
/// final class NotificationService: PushNotificationServiceExtension {}
/// ```
///
/// Stateless by design — it never calls or requires `PushNotificationService
/// .configure(siteId:)` to have run in its process (a Notification Service
/// Extension runs in its own OS process; there is nothing shared to call
/// into). Both `image` and `displayedUrl` already arrive as complete,
/// ready-to-use URLs in the notification payload. This is best-effort, not
/// guaranteed: the OS can skip service extensions under memory pressure or
/// Low Power Mode, and they run under a hard execution-time budget — a
/// missed `displayedUrl` ping here is expected occasionally, not a bug.
open class PushNotificationServiceExtension: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override open func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        Task {
            let processed = await Self.process(userInfo: content.userInfo, content: content, session: .shared)
            contentHandler(processed)
        }
    }

    override open func serviceExtensionTimeWillExpire() {
        // Deliver whatever we have — never let the OS show a blank/broken
        // notification because the time budget ran out mid-download.
        if let bestAttemptContent { contentHandler?(bestAttemptContent) }
    }

    static func process(userInfo: [AnyHashable: Any], content: UNMutableNotificationContent, session: URLSession) async -> UNMutableNotificationContent {
        // Runs concurrently with the image download below (async let), not
        // serially before it — a slow/hanging displayedUrl ping must not
        // consume the extension's whole execution budget and cost the
        // notification its image (see I3).
        async let pingTask: Void = pingDisplayedUrl(userInfo: userInfo, content: content, session: session)

        if let urlString = userInfo["image"] as? String, let url = URL(string: urlString),
           let data = try? await HTTPClient.get(url, session: session) {
            if let attachment = Self.attachment(from: data, url: url) {
                content.attachments = [attachment]
            }
        }

        await pingTask
        return content
    }

    /// If the NSE runs (mutable-content: 1 is set on every push, so it
    /// normally does) and successfully pings displayedUrl here, it stamps
    /// content.userInfo so PushNotificationService.handleDisplay (called
    /// later from willPresent, once the notification actually reaches
    /// display) skips its own ping — otherwise a foregrounded notification
    /// gets pinged twice, and DisplayController's counter is campaign-scoped
    /// with no per-device component, so the backend cannot dedupe it. Only
    /// stamped on SUCCESS: if the ping fails/times out here, no display was
    /// actually recorded, so handleDisplay must still get its chance to try.
    private static func pingDisplayedUrl(userInfo: [AnyHashable: Any], content: UNMutableNotificationContent, session: URLSession) async {
        guard let urlString = userInfo["displayedUrl"] as? String, let url = URL(string: urlString) else { return }
        if (try? await HTTPClient.get(url, session: session)) != nil {
            content.userInfo["_pnsDisplayPinged"] = true
        }
    }

    private static func attachment(from data: Data, url: URL) -> UNNotificationAttachment? {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
        do {
            try data.write(to: fileURL)
            return try UNNotificationAttachment(identifier: UUID().uuidString, url: fileURL)
        } catch {
            return nil
        }
    }
}
