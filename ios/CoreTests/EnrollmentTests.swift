import XCTest
@testable import BirthdayCore

@MainActor final class EnrollmentTests: XCTestCase {
  private var contract: EnrollmentContract {
    EnrollmentContract(
      approvalPath: { "/login?key=\($0)&name=Birthday%20Reminders&profile=fixture-birthday" },
      validate: { body in
        guard body["scopes"] as? [String] == ["tables:read:people:id"],
          let profile = body["enrollmentProfile"] as? [String: String],
          profile["id"] == "fixture-birthday", profile["revision"] == String(repeating: "a", count: 64)
        else { throw EnrollmentFailure("Synthetic profile rejected") }
        return EnrollmentProfileReceipt(id: profile["id"]!, revision: profile["revision"]!)
      })
  }
  private func approved(_ candidate: EnrollmentCandidate, scopes: [String] = ["tables:read:people:id"])
    -> EnrollmentReply {
    EnrollmentReply(status: 200, data: try! JSONSerialization.data(withJSONObject: [
      "name": "device:" + candidate.fingerprint, "scopes": scopes,
      "enrollmentProfile": ["id": "fixture-birthday", "revision": String(repeating: "a", count: 64)],
    ]))
  }

  func testCandidateIsFreshAndFingerprintMatchesPublishedAlgorithm() throws {
    let first = try EnrollmentCandidate.generate()
    let second = try EnrollmentCandidate.generate()
    XCTAssertNotEqual(first.token, second.token)
    XCTAssertTrue(first.token.hasPrefix("lt_"))
    XCTAssertEqual(first.token.count, 51)
    XCTAssertEqual(first.fingerprint.count, 64)
    XCTAssertEqual(EnrollmentCandidate(token: "abc").fingerprint,
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  func testUnavailableContractDoesNotGenerateCredentialOrCallNetwork() async {
    let model = EnrollmentSession(contract: nil,
      candidate: { XCTFail("must not create a candidate"); return .init(token: "fixture") },
      request: { _, _, _, _ in XCTFail("must not contact full-scope login"); return .init(status: 500) },
      install: { _, _, _, _, _ in XCTFail("must not install"); return true })
    await model.start(endpoint: "https://hub.example")
    XCTAssertEqual(model.phase, .idle)
    XCTAssertNil(model.approvalURL)
    XCTAssertNotNil(model.failure)
  }

  func testApprovalLinkContainsOnlyFingerprintAndAcceptedCandidateIsInstalled() async {
    let candidate = EnrollmentCandidate(token: "lt_synthetic")
    var installed = false
    var model: EnrollmentSession!
    model = EnrollmentSession(contract: contract, candidate: { candidate },
      request: { endpoint, token, revoke, _ in
        XCTAssertFalse(revoke)
        XCTAssertEqual(endpoint.absoluteString, "https://hub.example")
        XCTAssertEqual(token, candidate.token)
        XCTAssertEqual(model.approvalURL?.path, "/login")
        XCTAssertFalse(model.approvalURL!.absoluteString.contains(candidate.token))
        XCTAssertTrue(model.approvalURL!.absoluteString.contains(candidate.fingerprint))
        return self.approved(candidate)
      }, install: { _, token, _, current, accepted in
        XCTAssertEqual(token, candidate.token)
        XCTAssertTrue(current())
        installed = true
        accepted()
        return true
      })
    await model.start(endpoint: "https://hub.example")
    XCTAssertTrue(installed)
    XCTAssertEqual(model.phase, .connected)
    XCTAssertNil(model.approvalURL)
  }

  func testFullAdminWrongIdentityAndWrongProfileCannotInstall() async {
    let candidate = EnrollmentCandidate(token: "lt_synthetic")
    for reply in [approved(candidate, scopes: ["full"]), approved(candidate, scopes: ["admin"]),
      approved(candidate, scopes: ["tables:read"]), approved(.init(token: "different"))] {
      var revoked = false
      let model = EnrollmentSession(contract: contract, candidate: { candidate },
        request: { _, _, revoke, _ in
          if revoke { revoked = true; return .init(status: 200, data: Data(#"{"logged_out":true}"#.utf8)) }
          return reply
        }, install: { _, _, _, _, _ in XCTFail("invalid session installed"); return true })
      await model.start(endpoint: "https://hub.example")
      XCTAssertTrue(revoked)
      XCTAssertEqual(model.phase, .idle)
      XCTAssertNotNil(model.failure)
    }
  }

  func testPendingPollUsesDelayAndDeadlineWithoutInstallingLateResponse() async {
    let candidate = EnrollmentCandidate(token: "lt_synthetic")
    var clock = 0.0
    var polls = 0
    let model = EnrollmentSession(contract: contract, candidate: { candidate }, now: { clock },
      sleep: { seconds in XCTAssertEqual(seconds, 5); clock += seconds },
      request: { _, _, revoke, _ in
        if revoke { return .init(status: 401) }
        polls += 1
        if polls == 1 { return .init(status: 401) }
        clock = 301
        return self.approved(candidate)
      }, install: { _, _, _, _, _ in XCTFail("late approval installed"); return true })
    await model.start(endpoint: "https://hub.example")
    XCTAssertEqual(polls, 2)
    XCTAssertEqual(model.phase, .idle)
    XCTAssertNotNil(model.cleanupMessage)
    XCTAssertFalse(model.cleanupMessage!.contains("revoked."))
  }

  func testCancelFencesInflightApprovalAndRevokesOnlyCandidate() async {
    let candidate = EnrollmentCandidate(token: "lt_synthetic")
    var pending: CheckedContinuation<EnrollmentReply, Never>?
    let started = expectation(description: "request started")
    let model = EnrollmentSession(contract: contract, candidate: { candidate },
      request: { _, token, revoke, _ in
        XCTAssertEqual(token, candidate.token)
        if revoke { return .init(status: 200, data: Data(#"{"logged_out":true}"#.utf8)) }
        return await withCheckedContinuation { pending = $0; started.fulfill() }
      }, install: { _, _, _, _, _ in XCTFail("cancelled candidate installed"); return true })
    let run = Task { await model.start(endpoint: "https://hub.example") }
    await fulfillment(of: [started], timeout: 3)
    await model.cancel()
    pending?.resume(returning: approved(candidate))
    await run.value
    XCTAssertEqual(model.phase, .idle)
    XCTAssertNil(model.approvalURL)
    XCTAssertEqual(model.cleanupMessage, "Approval credential revoked.")
  }

  func testInvalidEndpointsAndCrossOriginApprovalNeverReachNetwork() async {
    for endpoint in ["http://hub.example", "https://u:p@hub.example", "https://hub.example?q=x",
      "https://hub.example#fragment"] {
      let model = EnrollmentSession(contract: contract,
        request: { _, _, _, _ in XCTFail("invalid endpoint used"); return .init(status: 500) },
        install: { _, _, _, _, _ in XCTFail(); return true })
      await model.start(endpoint: endpoint)
      XCTAssertNil(model.approvalURL)
      XCTAssertNotNil(model.failure)
    }
    let model = EnrollmentSession(contract: .init(
      approvalPath: { _ in "https://other.example/login" }, validate: { _ in .init(id: "fixture-birthday", revision: String(repeating: "a", count: 64)) }),
      request: { _, _, _, _ in XCTFail("cross-origin approval used"); return .init(status: 500) },
      install: { _, _, _, _, _ in XCTFail(); return true })
    await model.start(endpoint: "https://hub.example")
    XCTAssertNil(model.approvalURL)
  }

  func testReplacementFencesOldApproval() async {
    let first = EnrollmentCandidate(token: "lt_first")
    let second = EnrollmentCandidate(token: "lt_second")
    var generated = 0
    var pending: CheckedContinuation<EnrollmentReply, Never>?
    var installed: [String] = []
    let started = expectation(description: "first request started")
    let model = EnrollmentSession(contract: contract,
      candidate: { generated += 1; return generated == 1 ? first : second },
      request: { _, token, revoke, _ in
        if revoke { return .init(status: 200, data: Data(#"{"logged_out":true}"#.utf8)) }
        if token == first.token {
          return await withCheckedContinuation { pending = $0; started.fulfill() }
        }
        return self.approved(second)
      }, install: { _, token, _, current, accepted in
        guard current() else { return false }
        installed.append(token); accepted(); return true
      })
    let old = Task { await model.start(endpoint: "https://hub.example") }
    await fulfillment(of: [started], timeout: 3)
    await model.start(endpoint: "https://hub.example")
    pending?.resume(returning: approved(first))
    await old.value
    XCTAssertEqual(installed, [second.token])
    XCTAssertEqual(model.phase, .connected)
  }

  func testSuccessfulCommitIsNotRevokedWhenDeadlinePassesImmediatelyAfterIt() async {
    let candidate = EnrollmentCandidate(token: "lt_synthetic")
    var clock = 0.0
    let model = EnrollmentSession(contract: contract, candidate: { candidate }, now: { clock },
      request: { _, _, revoke, _ in
        XCTAssertFalse(revoke)
        return self.approved(candidate)
      }, install: { _, _, _, current, accepted in
        XCTAssertTrue(current())
        clock = 301
        accepted()
        return true
      })
    await model.start(endpoint: "https://hub.example")
    XCTAssertEqual(model.phase, .connected)
  }

  func testFailedInstallAttemptsCleanupWithoutClaimingConnection() async {
    let candidate = EnrollmentCandidate(token: "lt_synthetic")
    var revoked = false
    let model = EnrollmentSession(contract: contract, candidate: { candidate },
      request: { _, _, revoke, _ in
        if revoke { revoked = true; return .init(status: 401) }
        return self.approved(candidate)
      }, install: { _, _, _, current, accepted in XCTAssertTrue(current()); return false })
    await model.start(endpoint: "https://hub.example")
    XCTAssertTrue(revoked)
    XCTAssertEqual(model.phase, .idle)
    XCTAssertNotNil(model.failure)
    XCTAssertTrue(model.cleanupMessage!.contains("not confirmed"))
  }

  func testCancelAfterCommitDoesNotRevokeAcceptedConnection() async {
    let candidate = EnrollmentCandidate(token: "lt_synthetic")
    var model: EnrollmentSession!
    model = EnrollmentSession(contract: contract, candidate: { candidate },
      request: { _, _, revoke, _ in
        XCTAssertFalse(revoke)
        return self.approved(candidate)
      }, install: { _, _, _, current, accepted in
        XCTAssertTrue(current())
        accepted()
        await model.cancel()
        return true
      })
    await model.start(endpoint: "https://hub.example")
    XCTAssertEqual(model.phase, .connected)
  }

  func testReplacementRetainsUnconfirmedCleanupWarning() async {
    let first = EnrollmentCandidate(token: "lt_first")
    let second = EnrollmentCandidate(token: "lt_second")
    var generated = 0
    var pending: CheckedContinuation<EnrollmentReply, Never>?
    let started = expectation(description: "old request started")
    let cleaned = expectation(description: "old cleanup attempted")
    let model = EnrollmentSession(contract: contract,
      candidate: { generated += 1; return generated == 1 ? first : second },
      request: { _, token, revoke, _ in
        if revoke { cleaned.fulfill(); return .init(status: 401) }
        if token == first.token {
          return await withCheckedContinuation { pending = $0; started.fulfill() }
        }
        return self.approved(second)
      }, install: { _, _, _, current, accepted in
        guard current() else { return false }; accepted(); return true
      })
    let old = Task { await model.start(endpoint: "https://hub.example") }
    await fulfillment(of: [started], timeout: 3)
    await model.start(endpoint: "https://hub.example")
    await fulfillment(of: [cleaned], timeout: 3)
    pending?.resume(returning: approved(first))
    await old.value
    XCTAssertEqual(model.phase, .connected)
    XCTAssertTrue(model.cleanupMessage?.contains("not confirmed") == true)
  }

  func testRequestReceivesRemainingDeadline() async {
    let candidate = EnrollmentCandidate(token: "lt_synthetic")
    var clock = 0.0
    let model = EnrollmentSession(contract: contract, candidate: { candidate }, now: { clock },
      sleep: { _ in clock = 299 },
      request: { _, _, revoke, timeout in
        if revoke { return .init(status: 401) }
        if clock == 0 { return .init(status: 401) }
        XCTAssertEqual(timeout, 1)
        return self.approved(candidate)
      }, install: { _, _, _, current, accepted in
        XCTAssertTrue(current()); accepted(); return true
      })
    await model.start(endpoint: "https://hub.example")
    XCTAssertEqual(model.phase, .connected)
  }

  func testSessionTransportUsesCanonicalGetAndPostWithoutCookiesOrTokenURLs() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    let session = URLSession(configuration: config)
    for revoking in [false, true] {
      StubProtocol.handler = { request in
        XCTAssertEqual(request.url?.absoluteString, "https://hub.example/v1/session")
        XCTAssertEqual(request.httpMethod, revoking ? "POST" : "GET")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer lt_fixture")
        return (revoking ? 200 : 401, revoking ? #"{"logged_out":true}"# : "{}")
      }
      let reply = try await EnrollmentTransport.request(endpoint: URL(string: "https://hub.example")!,
        token: "lt_fixture", revoking: revoking, session: session)
      XCTAssertEqual(reply.status, revoking ? 200 : 401)
    }
  }

  func testOversizedSessionReplyIsRejected() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    StubProtocol.handler = { _ in (200, String(repeating: "x", count: 65_537)) }
    do {
      _ = try await EnrollmentTransport.request(endpoint: URL(string: "https://hub.example")!,
        token: "lt_fixture", revoking: false, session: URLSession(configuration: config))
      XCTFail("oversized reply accepted")
    } catch {}
  }
}
