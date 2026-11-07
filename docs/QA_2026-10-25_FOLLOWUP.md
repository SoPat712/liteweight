# liteweight visual follow-up — 2026-10-25

Owner requests and implementation:

- Home greeting/week card uses an opaque neutral surface, removing blue glass refraction.
- Library names use headline typography, with neutral muscle/equipment capsules and recency captions.
- Exercise detail keeps one title in the content header. Progress and target cards share native section gutters.
- The collapsed logger summary occupies its own row above a clipped scroll viewport, with a 12 pt bottom gap.
- Approved Previous capsules and 10 pt input outlines distinguish read-only history from editable values; completed blue fills remain.
- Remaining numeric typography in history, calendar, timers, RPE, plate/warm-up editors, settings and shared controls uses `Font.liteweightMetric`.
- Active rest takes priority over the Live Activity completion confirmation. Existing ActivityKit updates no longer wait for artwork IO.
- Interactive rest intents await state publication. The countdown suppresses placeholder invalidation and replacement animations.

Live Activity behavior has focused state/reconciliation regression coverage in `WorkoutDataTests.swift`.
The countdown rendering follows Apple's [interactive Live Activity guidance](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

Validation so far:

- Simulator app, widget/Siri targets and regression test bundle build passed.
- Signed iPhone/Watch Debug build passed.
- Eight checks against the actual shared phase resolver passed in an isolated Foundation harness.
- Focused XCTest retry remains blocked before execution by the simulator DTServiceHub/instruments service; the runner was stopped after 60 seconds.
- Default-light and AX3-dark screenshots reviewed: Home is neutral; library chips/titles follow liteweight; detail has one title and full-width cards; logger summary clears the clipped viewport at both sizes.
- Phone installation succeeded; launch was denied because the phone is locked.

[Screen comparison](/Users/joshp/.codex/visualizations/2026/10/25/01a1717b-ec55-7ea2-9c43-885e4b684d16/liteweight-followup/review.jpg).

The shared metric font helper now lives in `Shared/UI/SwiftUI/LiteweightMetricFont.swift` and is registered in all four UI targets that use the shared controls.

The simulator Lock Screen attempt did not display a Live Activity, so actual ±15 rendering
latency remains for verification on the phone after unlock. The simulated source-state checks
are not presented as a physical-device latency measurement. liteweight's simulator was restored to
light/default sizing and shut down after review.

All prior uncommitted work is preserved. No commits/pushes or changes to imported-workout Health eligibility.
