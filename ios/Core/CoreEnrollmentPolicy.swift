import CryptoKit
import Foundation
import JavaScriptCore

/// Runs the reviewed Soma Core enrollment policy without its replica runtime.
/// Profile selection is supplied by the service contract, never user token entry.
@MainActor public final class CoreEnrollmentPolicy {
  private let context: JSContext
  private let bridge: JSValue
  private let profile: [String: Any]

  public init(profileID: String, scopes: [String]) throws {
    guard let url = Bundle.module.url(forResource: "soma-enrollment", withExtension: "js"),
      let data = try? Data(contentsOf: url),
      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
        == "cd6a495dd3489a4161a7f7d3d8ce414cb77cc426636bac58181aace67cddcc2f",
      let source = String(data: data, encoding: .utf8), let context = JSContext()
    else { throw EnrollmentFailure("The approval policy could not be loaded.") }
    context.evaluateScript(source)
    guard context.exception == nil, let bridge = context.evaluateScript("""
      (function(operation, json) {
        const args = JSON.parse(json);
        if (operation === 'approval') return JSON.stringify(LifeEnrollment.enrollmentApproval(args));
        if (operation === 'validate') return JSON.stringify(LifeEnrollment.validateDeviceSession(args.data, args.expectedProfile));
        if (operation === 'revoke') return JSON.stringify(LifeEnrollment.sessionRevocationResult(args));
        throw new Error('Unsupported enrollment operation');
      })
      """), context.exception == nil else {
      throw EnrollmentFailure("The approval policy could not be loaded.")
    }
    self.context = context
    self.bridge = bridge
    self.profile = ["id": profileID, "scopes": scopes]
  }

  public var contract: EnrollmentContract {
    EnrollmentContract(approvalPath: { fingerprint in
      try self.approval(fingerprint)
    }, validate: { data in
      try self.validate(data)
    }, revoked: { reply in
      let data: Any = reply.data.isEmpty ? NSNull() : try JSONSerialization.jsonObject(with: reply.data)
      return try self.call("revoke", ["status": reply.status, "data": data])["state"] as? String == "revoked"
    })
  }

  private func approval(_ fingerprint: String) throws -> String {
    let result = try call("approval", ["fingerprint": fingerprint,
      "name": "Birthdays", "profile": profile["id"]!])
    guard let path = result["path"] as? String else { throw invalidResponse() }
    return path
  }

  private func validate(_ data: [String: Any]) throws -> EnrollmentProfileReceipt {
    let result = try call("validate", ["data": data, "expectedProfile": profile])
    guard let receipt = result["enrollmentProfile"] as? [String: String],
      let id = receipt["id"], let revision = receipt["revision"] else { throw invalidResponse() }
    return EnrollmentProfileReceipt(id: id, revision: revision)
  }

  private func call(_ operation: String, _ args: [String: Any]) throws -> [String: Any] {
    let json = String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)
    // Parse inside the JS realm: bridged NSDictionary is not a plain JS object.
    context.exception = nil
    let output = bridge.call(withArguments: [operation, json])
    guard context.exception == nil, let text = output?.toString(),
      let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    else { throw invalidResponse() }
    return value
  }

  private func invalidResponse() -> EnrollmentFailure {
    EnrollmentFailure("Soma did not approve birthday-only access for this device.")
  }
}
