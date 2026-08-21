# OffRent Ledger

**Idlery Services LLC** · native iPhone app · iOS 18+ · Swift and SwiftUI

> Know what every equipment rental is costing, capture the vendor's off-rent confirmation, track
> pickup, and check the final invoice — across every rental yard.

---

## Read this first

**OffRent Ledger does not contact rental companies and does not end rentals.** It is a ledger and
an evidence tool. It opens your phone dialler, it reminds you to get a confirmation number, and it
keeps what you recorded together — you make the call. That sentence is a product invariant, not a
disclaimer: it is enforced in the copy, in the state machine, and in a build-time check.

**The app in this repository has never been compiled.** It was built on Linux, with no macOS, no
Xcode and no iOS SDK. See [`TEST_MATRIX.md`](TEST_MATRIX.md) for exactly what was executed and
what was not, and [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) §1 for the first thing to do.

---

## The one architectural decision worth knowing

Everything that carries money, dates, state or parsing lives in `OffRentLedger/Domain/` and
`OffRentShared/`, which import **Foundation and nothing else**. Those two folders also compile as
a standalone SwiftPM module via the root `Package.swift`:

```swift
.target(name: "OffRentDomain", path: ".", sources: ["OffRentLedger/Domain", "OffRentShared"])
```

The *same files* the Xcode app target compiles. No copy, no vendoring, no sync step. Language mode
pinned to v5 to match the project's `SWIFT_VERSION`.

The consequence: **163 tests covering the rate engine, the state machine, the invoice comparison,
the OCR parser, the reminder planner, the entitlement policy and the export codecs ran and passed
on a machine with no Xcode at all.** Everything requiring Apple frameworks is a thin adapter over
that core, which keeps the unverifiable surface as small and as obvious as possible.

That is not a workaround for the environment. It is the architecture a testable iOS app should
have; the environment just made the cost of getting it wrong visible.

```
swift test                                   # 163 tests, ~0.5s
python3 scripts/verify_repository.py         # 30 repository invariants
python3 scripts/check_swift_call_sites.py    # every call site vs. its declaration
```

The app layer still has no compiler anywhere in this environment. The closest substitute is
`check_swift_call_sites.py`, which matches every `Type(...)` and `Type.staticFunc(...)` against
the signatures declared here — 91 types, 117 static functions, zero findings. It says nothing
about Apple's APIs. `RELEASE_CHECKLIST.md` §1 is still the real gate.

---

## Layout

```
OffRentLedger/
  App/             entry point, dependency container, routing, App Intents
  Configuration/   product name, URLs, product ids, required copy
  Domain/          PURE. Foundation only. Compiled twice — by Xcode and by SwiftPM.
  Persistence/     SwiftData models, versioned schema, migration plan, workflow service
  Services/        OCR, notifications, files, PDF, export/import, StoreKit, location, snapshot
  Features/        Today · Rentals · Scan · OffRent · Pickup · Audit · Subscription · Settings
  SharedUI/        design tokens, components, accessibility identifiers
  Resources/       asset catalog, bundled legal text, OCR fixtures
OffRentShared/     types the app and the widget must agree on exactly
OffRentLedgerWidget/
Tests/OffRentDomainTests/    ← the 163 that ran
OffRentLedgerTests/          ← written, needs Xcode
OffRentLedgerUITests/        ← written, needs a simulator
Website/          generated from the same Markdown the app bundles. Not deployed.
scripts/          project generator, asset generator, website generator, invariant checker
```

## Generated artefacts

Four things are generated and checked in CI, so they cannot drift from the code:

| File | Generator | Check |
|---|---|---|
| `OffRentLedger.xcodeproj/project.pbxproj` | `scripts/generate_xcodeproj.py` | `--check` |
| `docs/STATUS_TRANSITIONS.md` | `swift run offrent-docgen` | `--check` |
| `Website/*.html` | `scripts/generate_website.py` | `--check` |
| `Resources/Assets.xcassets` | `scripts/generate_assets.py` | — |

## Documents

| | |
|---|---|
| [`PROJECT_SOURCE_OF_TRUTH.md`](PROJECT_SOURCE_OF_TRUTH.md) | Authoritative. Product boundary, identifiers, architecture, what is unverified. |
| [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) | Phases, and what the environment made possible. |
| [`TEST_MATRIX.md`](TEST_MATRIX.md) | Written vs executed vs passed. Never conflated. |
| [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) | Everything a human still has to do. |
| [`docs/STATUS_TRANSITIONS.md`](docs/STATUS_TRANSITIONS.md) | Generated from the state machine. |
| [`docs/RISK_REGISTER.md`](docs/RISK_REGISTER.md) | Ordered by expected damage. |
| [`docs/FUTURE_EXPERIMENTS.md`](docs/FUTURE_EXPERIMENTS.md) | Deliberately out of scope for v1. |

## Privacy

No account, no server, no analytics, no ads, no tracking, no third-party crash reporter, no cloud
OCR, no background location, no third-party SDKs of any kind. Everything stays on the device.
`scripts/verify_repository.py` fails the build if a network client, an analytics symbol or a
tracking framework appears anywhere in the sources.

## CI

Four Codemagic workflows. Only one of them signs or uploads, and it refuses to start until the
credentials and App Store Connect records actually exist. None of them submits to the App Store.
