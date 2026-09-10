import Foundation

struct DeviceTokenAPI {
    let baseURL: URL
    let session: URLSession

    struct RegisterResponse: Decodable { let deviceToken: String }

    func register(siteId: String, platform: String, token: String, oldToken: String?, bundleId: String?, meta: [String: String]) async throws -> String {
        var body: [String: Any] = ["platform": platform, "token": token]
        if let oldToken { body["old_token"] = oldToken }
        if let bundleId { body["bundle_id"] = bundleId }
        if !meta.isEmpty { body["meta"] = meta }

        let data = try await post(path: "/v1/sites/\(siteId)/device-tokens", body: body)
        guard let decoded = try? JSONDecoder().decode(RegisterResponse.self, from: data) else {
            throw PushNotificationServiceError.invalidResponse
        }
        return decoded.deviceToken
    }

    func unregister(siteId: String, platform: String, token: String) async throws {
        _ = try await post(path: "/v1/sites/\(siteId)/device-tokens/unregister", body: ["platform": platform, "token": token])
    }

    private func post(path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Without this, a validation failure comes back as Laravel's default
        // HTML error page (500 to this client) instead of a JSON 422 — the
        // `api` route group content-negotiates on Accept, it doesn't infer
        // JSON from the request body alone.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Matches the Android SDK's explicit 15s connect/read timeout on the
        // same endpoint (DeviceTokenApi.kt) — URLSession's own default is
        // 60s, which is a real behavioral divergence between the two SDKs
        // against the same backend if left unset.
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            // JSONSerialization sits inside this same do/catch: `body` here
            // is always String/[String: String]-valued and cannot actually
            // fail to encode, but leaving the call outside the catch would
            // let a raw Foundation Error leak across the async throws
            // boundary instead of mapping to PushNotificationServiceError,
            // the one place the promised-exhaustive error mapping wouldn't
            // actually be exhaustive.
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            (data, response) = try await session.data(for: request)
        } catch {
            throw PushNotificationServiceError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw PushNotificationServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw PushNotificationServiceError.serverError(statusCode: http.statusCode)
        }
        return data
    }
}
