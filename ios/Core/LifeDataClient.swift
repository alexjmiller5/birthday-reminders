import Foundation

public struct PeopleSource: Codable, Equatable, Sendable {
  public var table = "people"
  public var nameColumn = "name"
  public var birthdayColumn = "birthday"
  public var enabledColumn = "notify_birthday"
  public init() {}
}

public final class LifeDataClient: @unchecked Sendable {
  private let endpoint: URL
  private let token: String
  private let session: URLSession
  public init(endpoint: String, token: String, session: URLSession = .shared) throws {
    guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
    else { throw BirthdayError.invalidEndpoint }
    self.endpoint = url
    self.token = token
    self.session = session
  }
  public func people(source: PeopleSource, includeRevisions: Bool = false) async throws -> [BirthdayPerson] {
    var people: [String: BirthdayPerson] = [:]
    var seenCursors: Set<String> = []
    var body: [String: Any] = [
      "table": source.table,
      "columns": [
        "id", source.nameColumn, source.birthdayColumn, source.enabledColumn, "deleted_at",
      ] + (includeRevisions ? ["updated_at", "hub_at"] : []),
      "since": "", "limit": 200,
    ]
    while true {
      let reply = try await request(path: "v1/rows/pull", body: body)
      guard let rows = reply["rows"] as? [[String: Any]], reply.keys.contains("next_cursor") else {
        throw BirthdayError.invalidResponse
      }
      for row in rows {
        guard row.keys.contains("deleted_at") else { throw BirthdayError.invalidResponse }
        if !(row["deleted_at"] is NSNull) { continue }
        guard let id = row["id"] as? String, !id.isEmpty,
          let name = row[source.nameColumn] as? String, !name.isEmpty,
          row.keys.contains(source.birthdayColumn), row.keys.contains(source.enabledColumn)
        else { throw BirthdayError.invalidResponse }
        if row[source.birthdayColumn] is NSNull || (row[source.birthdayColumn] as? String) == "" {
          continue
        }
        guard let birthday = row[source.birthdayColumn] as? String, BirthdayDate(birthday) != nil
        else { throw BirthdayError.invalidBirthday }
        let enabled = row[source.enabledColumn] as? Int
        guard enabled == 0 || enabled == 1 || row[source.enabledColumn] is NSNull else {
          throw BirthdayError.invalidResponse
        }
        people[id] = BirthdayPerson(id: id, name: name, birthday: birthday, enabled: enabled == 1,
          revision: includeRevisions ? try RowRevision.parse(row) : nil)
      }
      if reply["next_cursor"] is NSNull { return people.values.sorted { $0.id < $1.id } }
      guard let cursor = reply["next_cursor"] as? String, !cursor.isEmpty,
        seenCursors.insert(cursor).inserted
      else { throw BirthdayError.invalidResponse }
      body["after"] = cursor
    }
  }

  @MainActor public func setOptIn(_ person: BirthdayPerson, enabled: Bool, source: PeopleSource,
                                contract: EnrollmentContract) async throws -> BirthdayPerson {
    guard let revision = person.revision else { throw BirthdayError.invalidResponse }
    // A cached profile receipt is not current authorization. Validate the exact
    // live session through the canonical policy before submitting an edit.
    _ = try await contract.validate(request(path: "v1/session"))
    let receipt = try await request(path: "v1/rows/patch", body: [
      "table": source.table, "id": person.id, "values": [source.enabledColumn: enabled ? 1 : 0],
      "expected_revision": ["updated_at": revision.updatedAt, "hub_at": revision.hubAt as Any? ?? NSNull()],
    ])
    guard receipt["id"] as? String == person.id, let next = receipt["revision"] as? [String: Any]
    else { throw BirthdayError.invalidResponse }
    return BirthdayPerson(id: person.id, name: person.name, birthday: person.birthday,
                          enabled: enabled, revision: try RowRevision.parse(next))
  }

  private func request(path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
    var request = URLRequest(url: endpoint.appendingPathComponent(path))
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await session.data(for: request, delegate: NoRedirect())
    guard let response = response as? HTTPURLResponse else { throw BirthdayError.invalidResponse }
    if response.statusCode == 401 || response.statusCode == 403 { throw BirthdayError.unauthorized }
    guard (200...299).contains(response.statusCode) else {
      throw BirthdayError.http(response.statusCode)
    }
    guard data.count <= 5_000_000,
      let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw BirthdayError.invalidResponse }
    return reply
  }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
