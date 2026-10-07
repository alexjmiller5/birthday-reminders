#if DEBUG
import BirthdaysCore
import Foundation

/// Explicit development entry only. Release builds contain no fixture transport.
@MainActor enum BirthdayUITestFixture {
  static func model() -> BirthdayModel? {
    let args = ProcessInfo.processInfo.arguments
    guard args.contains("-birthdays-ui-fixture") || args.contains("-birthdays-clear-ui-fixture") else { return nil }
    let name = "birthdays-ui-fixture"
    let store = ConnectionStore(service: name)
    let defaults = UserDefaults(suiteName: name)!
    let cache = BirthdayCache(url: FileManager.default.temporaryDirectory.appendingPathComponent(name + ".json"))
    try? store.clear(); try? cache.clear(); defaults.removePersistentDomain(forName: name)
    guard args.contains("-birthdays-ui-fixture") else { return nil }
    let receipt = EnrollmentProfileReceipt(id: BirthdaysAccess.editorProfile, revision: String(repeating: "a", count: 64))
    try? store.save(Connection(endpoint: "https://example.invalid", token: "synthetic-ui-token", source: PeopleSource(), enrollmentProfile: receipt))
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [BirthdayFixtureProtocol.self]
    return BirthdayModel(cache: cache, credentials: store, defaults: defaults, session: URLSession(configuration: config))
  }
}

private final class BirthdayFixtureProtocol: URLProtocol {
  private static var enabled = false
  private static var edits = 0
  private static var revision: [String: String] {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let stamp = format.string(from: Date(timeIntervalSince1970: 1_893_456_000 + Double(edits)))
    return ["updated_at": stamp, "hub_at": stamp]
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let body: [String: Any]
    switch request.url!.path {
    case "/v1/session":
      body = ["name": "device:" + String(repeating: "b", count: 64), "scopes": BirthdaysAccess.editorScopes,
        "enrollmentProfile": ["id": BirthdaysAccess.editorProfile, "revision": String(repeating: "a", count: 64)],
        "capabilities": ["row_api": "v1", "schema": "none", "replica_sync": false, "conditional_patch": "revision-v1"]]
    case "/v1/rows/patch":
      Self.enabled.toggle()
      Self.edits += 1
      body = ["id": "fixture-a", "revision": Self.revision]
    default:
      body = ["rows": [("fixture-a", "<pérson-a>", "--01-01", Self.enabled), ("fixture-b", "<person-b>", "--02-01", true)].map { id, name, birthday, enabled -> [String: Any] in
        ["id": id, "name": name, "birthday": birthday, "notify_birthday": enabled ? 1 : 0,
         "deleted_at": NSNull(), "updated_at": Self.revision["updated_at"]!, "hub_at": Self.revision["hub_at"]!]
      }, "next_cursor": NSNull()]
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
#endif
