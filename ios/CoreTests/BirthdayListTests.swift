import XCTest
@testable import BirthdaysCore

final class BirthdayListTests: XCTestCase {
  private func row(_ id: String, _ name: String, _ day: Double, _ enabled: Bool = false) -> UpcomingBirthday {
    UpcomingBirthday(person: BirthdayPerson(id: id, name: name, birthday: "--01-01", enabled: enabled),
                     date: Date(timeIntervalSince1970: day))
  }

  func testSearchFoldsCaseAndAccentsAndTrimsWhitespace() {
    let rows = [row("1", "<PÉRSON-A>", 3), row("2", "<person-b>", 1)]
    XCTAssertEqual(BirthdayListOrder.apply(rows, search: "  person-a  ", rules: []).map(\.id), ["1"])
    XCTAssertEqual(BirthdayListOrder.apply(rows, search: "missing", rules: []).count, 0)
  }

  func testDefaultUsesOccurrenceDateAcrossYearBoundaryAndStableTies() {
    let rows = [row("b", "<person-b>", 200), row("c", "<person-c>", 100), row("a", "<person-a>", 100)]
    XCTAssertEqual(BirthdayListOrder.apply(rows, rules: BirthdaySortRule.defaults).map(\.id), ["a", "c", "b"])
    XCTAssertEqual(BirthdayListOrder.apply(rows.reversed(), rules: BirthdaySortRule.defaults).map(\.id), ["a", "c", "b"])
  }

  func testRulesAreOrderedAndIndividuallyReversible() {
    let rows = [row("1", "<person-b>", 3, true), row("2", "<person-a>", 1), row("3", "<person-c>", 2, true)]
    let enabledFirst = BirthdaySortRule(.notifications)
    let upcoming = BirthdaySortRule(.birthday)
    XCTAssertEqual(BirthdayListOrder.apply(rows, rules: [enabledFirst, upcoming]).map(\.id), ["3", "1", "2"])
    XCTAssertEqual(BirthdayListOrder.apply(rows, rules: [upcoming, enabledFirst]).map(\.id), ["2", "3", "1"])
    XCTAssertEqual(BirthdayListOrder.apply(rows, rules: [BirthdaySortRule(.notifications, reversed: true), BirthdaySortRule(.name, reversed: true)]).map(\.id), ["2", "3", "1"])
    XCTAssertEqual(BirthdayListOrder.apply(rows, rules: [BirthdaySortRule(.birthday, reversed: true)]).map(\.id), ["1", "3", "2"])
  }

  func testSortPreferencesRoundTripAndRemoveDuplicateRules() throws {
    let rules = [BirthdaySortRule(.name, reversed: true), BirthdaySortRule(.birthday)]
    XCTAssertEqual(try JSONDecoder().decode([BirthdaySortRule].self, from: JSONEncoder().encode(rules)), rules)
    XCTAssertEqual(BirthdayListOrder.normalized(rules + [BirthdaySortRule(.name)]), rules)
    XCTAssertEqual(BirthdayListOrder.normalized([]), BirthdaySortRule.defaults)
  }
}
