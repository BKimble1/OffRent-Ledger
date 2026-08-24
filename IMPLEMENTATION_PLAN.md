# OffRent Ledger — Implementation Plan

Phases are ordered so that each one leaves the repository in a coherent, reviewable state and each
commit maps to exactly one phase.

## Environment reality (established in Phase 0, drives everything below)

This build ran on **Ubuntu 24.04 x86_64**. There is no macOS, no Xcode, no iOS SDK, no simulator
and no device. `xcodebuild` does not exist and cannot be installed.

A **Swift 6.0.3 Linux toolchain was installed** during Phase 0 (from the SwiftWasm distribution of
the upstream toolchain, which carries a full host compiler). That gives a real `swiftc`,
SwiftPM, XCTest and swift-testing on this machine.

The consequence — and the single most important planning decision in this project:

> Everything that *can* be verified is pushed down into a Foundation-only `Domain` layer that
> compiles and tests on Linux. Everything that *cannot* be verified here is kept as a thin,
> boring adapter over that layer, so the unverifiable surface is as small and as obvious as
> possible.

That is not a workaround. It is the architecture that a testable iOS app should have anyway; the
environment simply made the cost of getting it wrong visible.

| Can be executed here | Cannot be executed here |
|---|---|
| Domain compilation (Swift 6.0.3) | App / widget / test-target compilation |
| Domain unit tests (XCTest, real) | XCTest on simulator, all UI tests |
| Property/fuzz tests over the rate engine | Anything touching SwiftUI, SwiftData, StoreKit, Vision |
| Repository invariant checks (Python) | Archive, signing, TestFlight |
| plist / JSON / YAML validation | Camera, notifications, location, widget, purchases |

## Phase 0 — Inspect and specify ✅

Repository safety gate; toolchain inspection; Swift-on-Linux bootstrap; `PROJECT_SOURCE_OF_TRUTH.md`;
architecture; domain model; status transition table; risk register; this plan.

## Phase 1 — Foundation ✅

Xcode project (`objectVersion = 77`, file-system-synchronized groups — the same shape that already
builds for this owner's other app, so the highest-risk unverifiable artefact is modelled on a known
-good one); `Config/Identifiers.xcconfig` centralising every identifier; Info.plists; entitlements;
shared scheme; SwiftData `SchemaV1` + `MigrationPlan`; `AppFileStore`; `Clock`; `AppDependencies`;
design tokens; tab shell; unit + UI test targets; root `Package.swift` exposing `Domain` +
`OffRentShared` as the portable `OffRentDomain` module.

## Phase 2 — Manual core workflow ✅

Today; Rentals list/detail/timeline; manual vendor, jobsite, agreement and item creation;
`StatusTransitionService`; Contact-Vendor state with the mandatory disclosure; confirmation
recording with explicit user affirmation; pickup recording; persistence and relaunch behaviour.
**Fully usable with no network, no account, no permission and no purchase.**

## Phase 3 — Scanning, OCR, reminders ✅

`VisionKit` document camera; PhotosPicker and PDF import; `VisionTextRecognizer`;
`DocumentTextParser` (pure) with confidence + provenance; the always-shown `ScanReviewView`;
`ReminderPlanner` (pure) + `UserNotificationScheduler`; `offrent://` deep links.

## Phase 4 — Invoice audit and evidence ✅

Invoice import and user-confirmed line items; `InvoiceComparisonEngine` (pure); `Discrepancy`
records and follow-up state; `EvidencePacketBuilder` (pure) + `PDFEvidenceRenderer`; CSV and JSON
export; import preview.

## Phase 5 — Monetization and widget ✅

`StoreKitSubscriptionService`; `EntitlementPolicy` (pure) enforcing the one-open-item free limit;
paywall; restore/manage; entitlement-loss preservation; App Group snapshot publisher; widget;
App Intents.

## Phase 6 — Release hardening ✅ (local work) / ⛔ (device work)

Accessibility pass; legal + privacy screens and the static `Website/`; App Review audit;
`scripts/verify_repository.py`; CI workflows (Codemagic at the time, GitHub Actions now); the real Linux test run;
honest completed-vs-unverified reporting.

**Not done, by instruction:** no App Store submission.
**Not doable, by environment:** every gate in `RELEASE_CHECKLIST.md` §3 and §4.
