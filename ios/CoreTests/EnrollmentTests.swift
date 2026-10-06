import XCTest
@testable import BirthdayCore

@MainActor final class EnrollmentTests: XCTestCase {
  private var contract: EnrollmentContract {
    EnrollmentContract(
      approvalPath: { "/synthetic-approval?key=\($0)" },
      accepts: { ($0["scopes"] as? [String]) == ["synthetic-birthday-read"] })
  }
  private func approved(_ candidate: EnrollmentCandidate, scopes: [String] = ["synthetic-birthday-read"])
    -> EnrollmentReply {
    EnrollmentReply(status: 200, data: try! JSONSerialization.data(withJSONObject: [
      "name": "device:" + candidate.fingerprint, "scopes": scopes,
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
      request: { _, _, _ in XCTFail("must not contact full-scope login"); return .init(status: 500) },
      install: { _, _, _ in XCTFail("must not install"); return true })
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
      request: { endpoint, token, revoke in
        XCTAssertFalse(revoke)
        XCTAssertEqual(endpoint.absoluteString, "https://hub.example")
        XCTAssertEqual(token, candidate.token)
        XCTAssertEqual(model.approvalURL?.path, "/synthetic-approval")
        XCTAssertFalse(model.approvalURL!.absoluteString.contains(candidate.token))
        XCTAssertTrue(model.approvalURL!.absoluteString.contains(candidate.fingerprint))
        return self.approved(candidate)
      }, install: { _, token, current in
        XCTAssertEqual(token, candidate.token)
        XCTAssertTrue(current())
        installed = true
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
        request: { _, _, revoke in
          if revoke { revoked = true; return .init(status: 200, data: Data(#"{"logged_out":true}"#.utf8)) }
          return reply
        }, install: { _, _, _ in XCTFail("invalid session installed"); return true })
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
      request: { _, _, revoke in
        if revoke { return .init(status: 401) }
        polls += 1
        if polls == 1 { return .init(status: 401) }
        clock = 301
        return self.approved(candidate)
      }, install: { _, _, _ in XCTFail("late approval installed"); return true })
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
      request: { _, token, revoke in
        XCTAssertEqual(token, candidate.token)
        if revoke { return .init(status: 200, data: Data(#"{"logged_out":true}"#.utf8)) }
        return await withCheckedContinuation { pending = $0; started.fulfill() }
      }, install: { _, _, _ in XCTFail("cancelled candidate installed"); return true })
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
        request: { _, _, _ in XCTFail("invalid endpoint used"); return .init(status: 500) },
        install: { _, _, _ in XCTFail(); return true })
      await model.start(endpoint: endpoint)
      XCTAssertNil(model.approvalURL)
      XCTAssertNotNil(model.failure)
    }
    let model = EnrollmentSession(contract: .init(
      approvalPath: { _ in "https://other.example/login" }, accepts: { _ in true }),
      request: { _, _, _ in XCTFail("cross-origin approval used"); return .init(status: 500) },
      install: { _, _, _ in XCTFail(); return true })
    await model.start(endpoint: "https://hub.example")
    XCTAssertNil(model.approvalURL)
  }
}
