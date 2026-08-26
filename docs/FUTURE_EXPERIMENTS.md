# Deliberately out of scope for v1

Each of these was considered and excluded because it crosses a v1 boundary in
`PROJECT_SOURCE_OF_TRUTH.md` §1.2. Recorded here so the decision is not re-litigated by accident.

| Idea | Boundary it crosses | Earliest sensible revisit |
|---|---|---|
| Submit off-rent requests to vendor portals | "does not contact rental companies" — the product's core honesty claim | Only with signed vendor integration agreements, and only as an *additional* channel that still records a user-obtained confirmation number |
| Email parsing of vendor invoices | inbox access; privacy posture | Post-v1, on-device mail extension only |
| QuickBooks / accounting sync | accounting software boundary | v2, export-only first |
| Multi-user company accounts, crew invitations | multi-tenant; requires a backend, auth, and a privacy policy rewrite | v2 |
| Telematics / meter-hour ingestion | telematics boundary | Never for v1; would also break the "no overtime calculation" rule |
| Automatic cheapest-rate optimisation | interprets vendor contract clauses the app cannot see | Only if vendors publish machine-readable terms |
| Localization beyond en-US | US-only v1 | v1.2 |
| Cloud sync / CloudKit | "no server" | v2, opt-in, would need a new privacy label |

## No longer out of scope

| Idea | Where it landed |
|---|---|
| iPad and landscape layouts | Shipped. `TARGETED_DEVICE_FAMILY = 1,2`, all four orientations on iPad, and a readable-width column so a list row is not thirteen hundred points wide. `IPadLayoutUITests` runs on a booted iPad simulator in CI's `ipad` job alongside the full core workflow. |
