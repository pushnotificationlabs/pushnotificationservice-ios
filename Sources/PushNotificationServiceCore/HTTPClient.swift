import Foundation

public enum HTTPClient {
    /// Performs a GET and returns the body on 2xx; throws otherwise. Used for
    /// the displayedUrl receipt ping (body discarded) and, by the extension
    /// kit, for downloading a notification image (body used).
    public static func get(_ url: URL, session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: url)
        // Matches DeviceTokenAPI.post()'s explicit 15s timeout (and the
        // Android SDK's equivalent) — URLSession's own default is 60s,
        // which inside a Notification Service Extension's hard time budget
        // (the caller of this function for image downloads) can burn the
        // entire budget on one slow request and cost the notification its
        // image or displayedUrl receipt.
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

public extension Data {
    /// Lowercase hex encoding — the format APNs device tokens must be sent
    /// in. `Data.description` ("<abcd 1234>") is NOT this and silently
    /// breaks registration if used by mistake.
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
