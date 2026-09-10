import Foundation

public enum PushNotificationServiceError: Error, Equatable {
    /// `didReceiveToken`/`unregister` called before `configure(siteId:)`.
    case notConfigured
    /// The server returned a non-2xx status.
    case serverError(statusCode: Int)
    /// The 2xx response body wasn't the expected shape.
    case invalidResponse
    /// A transport-level failure (no connectivity, timeout, etc.) — the
    /// underlying `Error` isn't carried to keep this type `Equatable` for
    /// tests; inspect the thrown error's `localizedDescription` if needed.
    case transport
}
