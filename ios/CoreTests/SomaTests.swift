import XCTest

@testable import BirthdaysCore

final class StubProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, String))!
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, body) = try Self.handler(request)
      client?.urlProtocol(
        self,
        didReceive: HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
        cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

final class SomaTests: XCTestCase {
  private func client() throws -> SomaClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return try SomaClient(
      endpoint: "https://example.invalid", token: "test-credential",
      session: URLSession(configuration: config))
  }

  func testPaginationExcludesTombstonesAndEmptyBirthdays() async throws {
    var requests = 0
    StubProtocol.handler = { request in
      requests += 1
      XCTAssertEqual(request.url?.path, "/v1/rows/pull")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-credential")
      let data: Data
      if let body = request.httpBody {
        data = body
      } else {
        let stream = request.httpBodyStream!
        stream.open()
        defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = stream.read(&bytes, maxLength: bytes.count)
        data = Data(bytes.prefix(count))
      }
      let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      XCTAssertEqual(body["table"] as? String, "people")
      XCTAssertEqual(
        body["columns"] as? [String], ["id", "name", "birthday", "notify_birthday", "deleted_at"])
      if requests == 1 {
        return (
          200,
          #"{"rows":[{"id":"p1","name":"<person-1>","birthday":"--02-29","notify_birthday":1,"deleted_at":null},{"id":"p2","name":"<person-2>","birthday":null,"notify_birthday":0,"deleted_at":null}],"next_cursor":"p2"}"#
        )
      }
      XCTAssertEqual(body["after"] as? String, "p2")
      return (
        200,
        #"{"rows":[{"id":"p3","name":"<person-3>","birthday":"2000-01-01","notify_birthday":1,"deleted_at":"2026-01-01"}],"next_cursor":null}"#
      )
    }
    let people = try await client().people(source: PeopleSource())
    XCTAssertEqual(
      people, [BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--02-29", enabled: true)])
    XCTAssertEqual(requests, 2)
  }

  func testUnauthorizedReadsFailClosed() async throws {
    for reply in [(401, "{}"), (403, "{}")] {
      StubProtocol.handler = { _ in reply }
      do {
        _ = try await client().people(source: PeopleSource())
        XCTFail("Invalid credential accepted")
      } catch {}
    }
  }

  func testMalformedResponseAndRepeatedCursorFailClosed() async throws {
    for body in [
      "{}",
      #"{"rows":[{"id":"p1","name":"<person-1>","birthday":"--02-30","notify_birthday":1,"deleted_at":null}],"next_cursor":null}"#,
      #"{"rows":[],"next_cursor":"p1"}"#,
    ] {
      StubProtocol.handler = { _ in (200, body) }
      do {
        _ = try await client().people(source: PeopleSource())
        XCTFail("Invalid snapshot accepted")
      } catch {}
    }
  }

  func testRejectsCredentialBearingOrInsecureURLs() {
    for url in [
      "http://example.invalid", "https://u:p@example.invalid", "https://example.invalid?token=x",
      "https://example.invalid#x",
    ] {
      XCTAssertThrowsError(try SomaClient(endpoint: url, token: "test"))
    }
  }

  func testRedirectResponseIsRejected() async throws {
    var requests = 0
    StubProtocol.handler = { _ in
      requests += 1
      return (302, "{}")
    }
    do {
      _ = try await client().people(source: PeopleSource())
      XCTFail("Redirect response accepted")
    } catch BirthdayError.http(let status) {
      XCTAssertEqual(status, 302)
    }
    XCTAssertEqual(requests, 1)
  }
}
