# OffRentLedgerUITests

Deliberately small. Six scenarios, each of which would be a shipped defect if it broke, and
nothing else. A large UI suite that nobody runs because it takes twenty minutes is worse than a
short one that runs on every push.

Every test launches with `-offrent-in-memory-store`, a fixed clock and a stubbed text recogniser,
so none of them depends on the wall clock, the camera, the network, or a previous test's state.
Those launch arguments are **ignored in Release builds** — see `AppDependencies.testOverrides`.

**These were written but NOT executed.** No macOS, no Xcode, no simulator in the build
environment. See `TEST_MATRIX.md`.
