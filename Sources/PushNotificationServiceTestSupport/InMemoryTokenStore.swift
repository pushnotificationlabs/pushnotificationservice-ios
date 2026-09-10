import Foundation

public final class InMemoryTokenStore {
    private var token: String?
    public init(initial: String? = nil) { self.token = initial }
    public func load() -> String? { token }
    public func save(_ token: String) { self.token = token }
    public func clear() { token = nil }
}
