// swift-tools-version: 6.0
import PackageDescription

// This package exists so that the parts of OffRent Ledger that carry money, dates, state and
// parsing can be compiled and tested on any machine with a Swift toolchain — including one with
// no Xcode at all.
//
// It does not vendor or copy anything. `sources` points at the very same folders the Xcode app
// target compiles, so there is exactly one copy of every file and the tests below run against
// the code that ships. Both folders are Foundation-only by rule; `scripts/verify_repository.py`
// fails the build if a SwiftUI, SwiftData, StoreKit, Vision or UIKit import appears in either.
//
// The language mode is pinned to v5 to match `SWIFT_VERSION = 5.0` in the Xcode project, so a
// compile here is evidence about the compile there.
let package = Package(
    name: "OffRentDomain",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OffRentDomain", targets: ["OffRentDomain"]),
        .executable(name: "offrent-docgen", targets: ["DocGen"]),
    ],
    targets: [
        .target(
            name: "OffRentDomain",
            path: ".",
            // `path: "."` means SwiftPM sees the whole repository, so everything that is not one
            // of the two portable source folders has to be named here. Adding a new top-level
            // folder without adding it to this list produces an "unhandled files" warning, which
            // is the intended nudge rather than a silent inclusion.
            exclude: [
                "Config", "StoreKit", "Tests", "Website", "docs", "scripts",
                "OffRentLedger.xcodeproj", "OffRentLedgerTests", "OffRentLedgerUITests",
                "OffRentLedgerWidget", "codemagic.yaml", "README.md",
                "PROJECT_SOURCE_OF_TRUTH.md", "IMPLEMENTATION_PLAN.md",
                "TEST_MATRIX.md", "RELEASE_CHECKLIST.md",
                "OffRentLedger/App", "OffRentLedger/Configuration", "OffRentLedger/Features",
                "OffRentLedger/Persistence", "OffRentLedger/Resources",
                "OffRentLedger/Services", "OffRentLedger/SharedUI", "Tools",
            ],
            sources: ["OffRentLedger/Domain", "OffRentShared"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DocGen",
            dependencies: ["OffRentDomain"],
            path: "Tools/DocGen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OffRentDomainTests",
            dependencies: ["OffRentDomain"],
            path: "Tests/OffRentDomainTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
