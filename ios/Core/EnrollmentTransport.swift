import Foundation

/// Existing service operations only: GET session to poll; POST session to revoke.
public enum EnrollmentTransport {
  public static func endpoint(_ input: String) throws -> URL {
    guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme == "https", let host = url.host, !host.isEmpty,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
    else { throw BirthdayError.invalidEndpoint }
    return url
  }

  public static func request(endpoint: URL, token: String, revoking: Bool, timeout: Double) async throws -> EnrollmentReply {
    try await request(endpoint: endpoint, token: token, revoking: revoking, timeout: timeout, session: .shared)
  }

  static func request(endpoint: URL, token: String, revoking: Bool, timeout: Double = 30, session: URLSession) async throws -> EnrollmentReply {
    let endpoint = try self.endpoint(endpoint.absoluteString)
    guard timeout.isFinite, timeout > 0 else { throw URLError(.timedOut) }
    let configuration = session.configuration
    configuration.timeoutIntervalForRequest = min(30, timeout)
    configuration.timeoutIntervalForResource = min(30, timeout)
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    let boundedSession = URLSession(configuration: configuration)
    defer { boundedSession.invalidateAndCancel() }
    var request = URLRequest(url: endpoint.appendingPathComponent("v1/session"))
    request.httpMethod = revoking ? "POST" : "GET"
    request.httpShouldHandleCookies = false
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = min(30, timeout)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (bytes, response) = try await boundedSession.bytes(for: request, delegate: EnrollmentNoRedirect())
    guard let response = response as? HTTPURLResponse else {
      throw EnrollmentFailure("Invalid approval response.")
    }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 65_536 else { throw EnrollmentFailure("Approval response was too large.") }
      data.append(byte)
    }
    return EnrollmentReply(status: response.statusCode, data: data,
      retryAfterSeconds: response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
  }
}

private final class EnrollmentNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}
