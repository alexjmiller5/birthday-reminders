import Foundation

/// Public, service-owned approval profile. Neither the Tasks writer nor a full
/// replica credential is eligible for this phone connection.
public enum BirthdaysAccess {
  public static let editorProfile = "birthdays-editor-v1"
  public static let editorScopes = [
    "tables:read:people:birthday", "tables:read:people:deleted_at", "tables:read:people:id",
    "tables:read:people:name", "tables:read:people:notify_birthday",
    "tables:read:people:updated_at", "tables:read:people:hub_at",
    "tables:patch:people:notify_birthday",
  ]
  @MainActor public static func editorContract() throws -> EnrollmentContract {
    try CoreEnrollmentPolicy(profileID: editorProfile, scopes: editorScopes).contract
  }
}
