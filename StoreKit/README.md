# StoreKit configuration

`OffRentLedger.storekit` is a **local test configuration**. It is what the scheme points at so
that purchases can be exercised in the simulator without an App Store Connect record.

It is **not** the production subscription setup and does not create one. The two product
identifiers here must be created by hand in App Store Connect, in a single subscription group,
before any Sandbox or TestFlight purchase can work:

| Product ID | Type | Intended US price |
| --- | --- | --- |
| `com.idlery.offrent.pro.monthly` | Auto-renewable, P1M | $14.99 |
| `com.idlery.offrent.pro.annual` | Auto-renewable, P1Y | $119.99 |

The prices above appear here and in `PROJECT_SOURCE_OF_TRUTH.md` only. **The app never renders
them.** Every price shown to a user comes from `Product.displayPrice`, so a price change in App
Store Connect needs no app update and the app cannot display a stale figure.

`_developerTeamID` is carried over from the owner's existing project and is unverified — see
`RELEASE_CHECKLIST.md` §3.

A passing test against this file proves the app's entitlement logic. It proves nothing about
production purchases: Sandbox and TestFlight are separate, real-device gates.
