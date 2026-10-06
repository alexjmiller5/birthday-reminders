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
  public let approvalPath: (String) async throws -> String
  public let validate: ([String: Any]) async throws -> EnrollmentProfileReceipt
  public init(approvalPath: @escaping (String) async throws -> String,
              validate: @escaping ([String: Any]) async throws -> EnrollmentProfileReceipt) {
    self.approvalPath = approvalPath
    self.validate = validate
  }
}

/// Evidence returned by the canonical profile validator, not a grant request.
public struct EnrollmentProfileReceipt: Codable, Equatable, Sendable {
  public let id: String
  public let revision: String
  public init(id: String, revision: String) { self.id = id; self.revision = revision }
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
  private var cleanupMessages: [String: String] = [:]
  public var cleanupMessage: String? {
    cleanupMessages.isEmpty ? nil : cleanupMessages.sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n")
  }
  public var available: Bool { contract != nil }

  public typealias Request = (URL, String, Bool, Double) async throws -> EnrollmentReply
  public typealias Install = (String, String, EnrollmentProfileReceipt, @escaping @MainActor () -> Bool,
                             @escaping @MainActor () -> Void) async -> Bool
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
    if let previous {
      cleanupMessages[previous.candidate.fingerprint] = "Previous approval cleanup is not confirmed yet."
      Task { await cleanup(previous) }
    }
    clearApproval()
    failure = nil
    phase = .idle
    do {
      let endpoint = try EnrollmentTransport.endpoint(endpoint)
      guard let contract else {
        throw EnrollmentFailure("Birthday-only approval is not available yet. You can still test notifications in Settings.")
      }
      let candidate = try candidate()
      let path = try await contract.approvalPath(candidate.fingerprint)
      guard generation == id, !Task.isCancelled else { throw CancellationError() }
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
          reply = try await request(endpoint, candidate.token, false, min(30, next.deadline - now()))
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
            !scopes.contains("full"), !scopes.contains("admin")
          else { throw EnrollmentFailure("Life Data did not approve birthday-only access for this device.") }
          let receipt = try await contract.validate(body)
          try check(next)
          phase = .installing
          let installed = await install(endpoint.absoluteString, candidate.token, receipt, { [weak self] in
            guard let self else { return false }
            return (try? self.check(next)) != nil
          }, { [weak self] in
            guard let self, self.generation == id else { return }
            // Called synchronously at the persistence commit, before yielding.
            self.attempt = nil
            self.phase = .connected
            self.clearApproval()
          })
          guard generation == id else { return }
          if phase == .connected { return }
          try check(next)
          guard installed else { throw EnrollmentFailure("Could not save the approved connection. Your previous connection is unchanged.") }
          throw EnrollmentFailure("The connection was not committed. Try again.")
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
        await cleanup(previous)
      }
    }
  }

  public func cancel() async {
    guard phase != .connected else { return }
    generation += 1
    let previous = attempt
    attempt = nil
    phase = .idle
    clearApproval()
    guard let previous else { return }
    await cleanup(previous)
  }

  private func check(_ value: Attempt) throws {
    guard value.generation == generation, !Task.isCancelled else { throw CancellationError() }
    guard now() < value.deadline else {
      throw EnrollmentFailure("This approval request expired. Start again for a new link.")
    }
  }

  private func cleanup(_ value: Attempt) async {
    let fingerprint = value.candidate.fingerprint
    cleanupMessages[fingerprint] = "Approval cleanup is not confirmed yet."
    let message = await Task { @MainActor in
      if let reply = try? await request(value.endpoint, value.candidate.token, true, 30),
        reply.status == 200, reply.data.count <= 65_536,
        let body = try? JSONSerialization.jsonObject(with: reply.data) as? [String: Any],
        body["logged_out"] as? Bool == true {
        return "Approval credential revoked."
      }
      return "Revocation is not confirmed. If you approve the old link later, revoke that device in Life Data."
    }.value
    cleanupMessages[fingerprint] = message
  }

  private func clearApproval() {
    approvalURL = nil
    approvalCode = nil
  }
}
