import Foundation

/// The product's name and company, in one place.
///
/// It lives in `OffRentShared` rather than in the app's `Configuration` folder because three
/// separate compilation units need it: the app, the widget extension, and the portable
/// `OffRentDomain` package that the domain tests build. A constant in the app target would be
/// invisible to two of the three, and the usual result of that is three copies that drift.
///
/// `scripts/verify_repository.py` fails the build if the literal appears anywhere else, so
/// changing the working name is this file plus `OFFRENT_DISPLAY_NAME` in `Identifiers.xcconfig`.
enum SharedBranding {
    static let displayName = "OffRent Ledger"
    static let companyName = "Idlery Services LLC"
    static let companyShortName = "Idlery"
}
