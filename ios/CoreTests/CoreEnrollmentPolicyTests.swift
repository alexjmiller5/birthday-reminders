import XCTest
@testable import BirthdaysCore

@MainActor final class CoreEnrollmentPolicyTests: XCTestCase {
  private let fingerprint = String(repeating: "b", count: 64)
  private let revision = String(repeating: "a", count: 64)
  private let scopes = ["tables:read:people:id", "tables:read:people:birthday"]

  private var session: [String: Any] {
    ["name": "device:" + fingerprint, "scopes": scopes,
     "enrollmentProfile": ["id": "fixture-birthday", "revision": revision],
     "capabilities": ["row_api": "v1", "schema": "none", "replica_sync": false]]
  }

  func testEditorRequiresExactFieldGrantAndConditionalPatchCapability() async throws {
    let contract = try BirthdaysAccess.editorContract()
    let path = try await contract.approvalPath(fingerprint)
    XCTAssertTrue(path.contains("profile=birthdays-editor-v1"))
    var value = session
    value["scopes"] = BirthdaysAccess.editorScopes
    value["enrollmentProfile"] = ["id": BirthdaysAccess.editorProfile, "revision": revision]
    do { _ = try await contract.validate(value); XCTFail("Missing patch capability accepted") } catch {}
    value["capabilities"] = ["row_api": "v1", "schema": "none", "replica_sync": false, "conditional_patch": "revision-v1"]
    let receipt = try await contract.validate(value)
    XCTAssertEqual(receipt.id, BirthdaysAccess.editorProfile)
    value["scopes"] = BirthdaysAccess.editorScopes + ["tables:write:people"]
    do { _ = try await contract.validate(value); XCTFail("Whole-table write accepted") } catch {}
  }

  func testRenamedProductionProfileRejectsRetiredProfileReceipt() async throws {
    let grants = ["tables:read:people:birthday", "tables:read:people:deleted_at", "tables:read:people:id",
                  "tables:read:people:name", "tables:read:people:notify_birthday"]
    let policy = try CoreEnrollmentPolicy(profileID: "birthdays-reader-v1", scopes: grants)
    let path = try await policy.contract.approvalPath(fingerprint)
    XCTAssertTrue(path.contains("profile=birthdays-reader-v1"))
    var value = session
    value["scopes"] = grants
    value["enrollmentProfile"] = ["id": "birthday-reminders-reader-v1", "revision": revision]
    do { _ = try await policy.contract.validate(value); XCTFail("Retired profile accepted") }
    catch {}
    value["enrollmentProfile"] = ["id": "birthdays-reader-v1", "revision": revision]
    let receipt = try await policy.contract.validate(value)
    XCTAssertEqual(receipt.id, "birthdays-reader-v1")
  }

  func testCanonicalApprovalAndProfileReceiptThroughJavaScriptCore() async throws {
    let policy = try CoreEnrollmentPolicy(profileID: "fixture-birthday", scopes: scopes)
    let path = try await policy.contract.approvalPath(fingerprint)
    let url = try XCTUnwrap(URLComponents(string: "https://hub.example" + path))
    XCTAssertEqual(url.path, "/login")
    XCTAssertEqual(url.queryItems?.first { $0.name == "key" }?.value, fingerprint)
    XCTAssertEqual(url.queryItems?.first { $0.name == "profile" }?.value, "fixture-birthday")
    let receipt = try await policy.contract.validate(session)
    XCTAssertEqual(receipt, EnrollmentProfileReceipt(id: "fixture-birthday", revision: revision))
  }

  func testCanonicalPolicyRejectsExpandedAuthorityAndInvalidReceipts() async throws {
    let policy = try CoreEnrollmentPolicy(profileID: "fixture-birthday", scopes: scopes)
    var variants = [[String: Any]]()
    for grants in [["full"], scopes + ["tables:write:tasks"], scopes + [scopes[0]], [scopes[0]]] {
      var value = session; value["scopes"] = grants; variants.append(value)
    }
    for receipt in [["id": "different", "revision": revision],
                    ["id": "fixture-birthday", "revision": "1"]] {
      var value = session; value["enrollmentProfile"] = receipt; variants.append(value)
    }
    for caps: [String: Any] in [
      ["row_api": "v1", "schema": "full-ddl-v1", "replica_sync": true],
      ["row_api": "v1", "schema": "none", "replica_sync": false, "governance": NSNull()],
    ] {
      var value = session; value["capabilities"] = caps; variants.append(value)
    }
    for value in variants {
      do { _ = try await policy.contract.validate(value); XCTFail("Expanded or invalid authority accepted") }
      catch { /* Canonical Core policy must reject. */ }
    }
    // A thrown JS exception must not poison the next valid evaluation.
    let receipt = try await policy.contract.validate(session)
    XCTAssertEqual(receipt.revision, revision)
  }
}
