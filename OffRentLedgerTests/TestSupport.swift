import Foundation

/// Shared fixtures for the app-target test bundle.
///
/// Mirrors `Tests/OffRentDomainTests/TestSupport.swift`, which serves the portable domain suite.
/// The two cannot be one file: they belong to different modules, and this one is allowed to
/// `@testable import OffRentLedger` while the portable one deliberately is not.

/// A money fixture, parsed the way the app parses money.
///
/// `Decimal(string:)` without a locale argument is not the same function: it reads the string
/// through whatever locale the device is set to, so `money("310.00")` on a device set to German
/// is not 310.00. Every money literal in a test goes through here for the same reason
/// `MoneyMath.parse` pins `en_US_POSIX` on the path the user's typing takes.
///
/// `fatalError` rather than an optional return: a fixture string that does not parse is a broken
/// test, not a test failure, and it should stop at the fixture rather than one assertion later.
func money(_ string: String) -> Decimal {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        fatalError("Test fixture money is not parseable: \(string)")
    }
    return value
}
