import CryptoKit
import Foundation
import Observation
import Security

public struct EnrollmentCandidate: Sendable {
  public let token: String
  public var fingerprint: String {
    SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  public static func generate() throws -> Self {
    var bytes = [UInt8](repeating: 0, count: 24)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw EnrollmentFailure("Could not prepare secure approval. Try again.")
    }
    return Self(token: "lt_" + bytes.map { String(format: "%02x", $0) }.joined())
  }
}

/// The service's canonical profile binding supplies both operations together.
/// No production binding exists until Life Core publishes narrow enrollment.
/// In particular, do not bind this to the legacy full-scope /login operation.
public struct EnrollmentContract {
  public let approvalPath: (String) throws -> String
  public let accepts: ([String: Any]) throws -> Bool
  public init(approvalPath: @escaping (String) throws -> String,
              accepts: @escaping ([String: Any]) throws -> Bool) {
    self.approvalPath = approvalPath
    self.accepts = accepts
  }
}

public struct EnrollmentReply {
  public let status: Int
  public let data: Data
  public let retryAfterSeconds: Double?
  public init(status: Int, data: Data = Data(), retryAfterSeconds: Double? = nil) {
    self.status = status
    self.data = data
    self.retryAfterSeconds = retryAfterSeconds
  }
}

struct EnrollmentFailure: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

@MainActor @Observable public final class EnrollmentSession {
  public enum Phase { case idle, waiting, installing, connected }
  public private(set) var phase = Phase.idle
  public private(set) var approvalURL: URL?
  public private(set) var approvalCode: String?
  public private(set) var failure: String?
  public private(set) var cleanupMessage: String?
  public var available: Bool { contract != nil }

  public typealias Request = (URL, String, Bool) async throws -> EnrollmentReply
  public typealias Install = (String, String, @escaping @MainActor () -> Bool) async -> Bool
  private let contract: EnrollmentContract?
  private let candidate: () throws -> EnrollmentCandidate
  private let now: () -> Double
  private let sleep: (Double) async throws -> Void
  private let request: Request
  private let install: Install
  private var generation = 0
  private var attempt: Attempt?
  private struct Attempt {
    let generation: Int
    let endpoint: URL
    let candidate: EnrollmentCandidate
    let deadline: Double
  }

  public init(contract: EnrollmentContract?,
              candidate: @escaping () throws -> EnrollmentCandidate = EnrollmentCandidate.generate,
              now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
              sleep: @escaping (Double) async throws -> Void = {
                try await Task.sleep(for: .seconds($0))
              },
              request: @escaping Request = EnrollmentTransport.request,
              install: @escaping Install) {
    self.contract = contract
    self.candidate = candidate
    self.now = now
    self.sleep = sleep
    self.request = request
    self.install = install
  }

  public func start(endpoint: String) async {
    generation += 1
    let id = generation
    let previous = attempt
    attempt = nil
    if let previous { Task { _ = await cleanup(previous) } }
    clearApproval()
    failure = nil
    cleanupMessage = nil
    phase = .idle
    do {
      let endpoint = try EnrollmentTransport.endpoint(endpoint)
      guard let contract else {
        throw EnrollmentFailure("Birthday-only approval is not available yet. You can still test notifications in Settings.")
      }
      let candidate = try candidate()
      let path = try contract.approvalPath(candidate.fingerprint)
      guard path.hasPrefix("/"), !path.hasPrefix("//"),
        let link = URL(string: path, relativeTo: endpoint)?.absoluteURL,
        link.scheme == endpoint.scheme, link.host == endpoint.host, link.port == endpoint.port,
        link.user == nil, link.password == nil, link.fragment == nil,
        !(link.absoluteString.removingPercentEncoding ?? "").contains(candidate.token)
      else { throw EnrollmentFailure("Life Data returned an invalid approval link.") }
      let next = Attempt(generation: id, endpoint: endpoint, candidate: candidate, deadline: now() + 300)
      attempt = next
      approvalURL = link
      approvalCode = String(candidate.fingerprint.prefix(8))
      phase = .waiting
      while true {
        try check(next)
        let reply: EnrollmentReply
        do {
          reply = try await request(endpoint, candidate.token, false)
        } catch is URLError {
          try check(next)
          try await sleep(min(5, next.deadline - now()))
          continue
        }
        try check(next)
        guard reply.data.count <= 65_536 else { throw EnrollmentFailure("Invalid approval response.") }
        if reply.status == 200 {
          guard let body = try JSONSerialization.jsonObject(with: reply.data) as? [String: Any],
            body["name"] as? String == "device:" + candidate.fingerprint,
            let scopes = body["scopes"] as? [String],
            !scopes.contains("full"), !scopes.contains("admin"), try contract.accepts(body)
          else { throw EnrollmentFailure("Life Data did not approve birthday-only access for this device.") }
          phase = .installing
          let installed = await install(endpoint.absoluteString, candidate.token) { [weak self] in
            guard let self else { return false }
            return (try? self.check(next)) != nil
          }
          try check(next)
          guard installed else { throw EnrollmentFailure("Could not save the approved connection. Your previous connection is unchanged.") }
          attempt = nil
          phase = .connected
          clearApproval()
          return
        }
        guard [401, 403, 429].contains(reply.status) || (500...599).contains(reply.status) else {
          throw EnrollmentFailure("Life Data could not complete approval. Try again.")
        }
        let retry = [429, 503].contains(reply.status) ? reply.retryAfterSeconds ?? 5 : 5
        let delay = retry.isFinite ? max(5, retry) : 5
        try await sleep(min(delay, max(0, next.deadline - now())))
      }
    } catch {
      guard generation == id else { return }
      let previous = attempt
      attempt = nil
      phase = .idle
      clearApproval()
      failure = (error as? EnrollmentFailure)?.message ?? "Approval could not finish. Try again."
      if let previous {
        let message = await cleanup(previous)
        if generation == id { cleanupMessage = message }
      }
    }
  }

  public func cancel() async {
    generation += 1
    let id = generation
    let previous = attempt
    attempt = nil
    phase = .idle
    clearApproval()
    guard let previous else { return }
    let message = await cleanup(previous)
    if generation == id { cleanupMessage = message }
  }

  private func check(_ value: Attempt) throws {
    guard value.generation == generation, !Task.isCancelled else { throw CancellationError() }
    guard now() < value.deadline else {
      throw EnrollmentFailure("This approval request expired. Start again for a new link.")
    }
  }

  private func cleanup(_ value: Attempt) async -> String {
    await Task { @MainActor in
      if let reply = try? await request(value.endpoint, value.candidate.token, true),
        reply.status == 200, reply.data.count <= 65_536,
        let body = try? JSONSerialization.jsonObject(with: reply.data) as? [String: Any],
        body["logged_out"] as? Bool == true {
        return "Approval credential revoked."
      }
      return "Revocation is not confirmed. If you approve the old link later, revoke that device in Life Data."
    }.value
  }

  private func clearApproval() {
    approvalURL = nil
    approvalCode = nil
  }
}
