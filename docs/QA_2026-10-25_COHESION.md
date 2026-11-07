# Cohesion, exercise recovery and navigation QA — 2026-10-25

The owner rejected the earlier partial typography pass. This pass compared complete pages
at matching default/light appearance, including Home's lower sections, then checked selected
screens in dark/AX3. Root tabs, exercise detail/history, completed workout and active logger
were inspected. Native form/chrome text remains native; data-row titles, inline summaries,
metric values/units, tags, buttons and nested corner tokens now share the documented hierarchy.

Changes found by rendering included oversized Body rows, separators aligned only under values,
History summaries smaller than Workout summaries, and AX3 measurement changes visually running
into absolute values. Body now uses native row spacing, full content separators and vertically
separate changes at accessibility sizes. Focused logger values use bold rather than heavy;
compact values use title3. Custom Exercises shares the illustrated library row.

Evidence is under
`/Users/joshp/.codex/visualizations/2026/10/25/01a1717b-ec55-7ea2-9c43-885e4b684d16/liteweight-cohesion/`:

- `cohesion-review.jpg`: matching default/light Home top/lower, logger, History, Workout, library.
- `final-*-dark-ax3.png`: Home, library, detail, History and collapsed logger at AX3/dark.
- `final-home-body-ax3-separated-change.png`: final measurement layout correction.
- `media-leg-raise-search.png`: real recovered picture/metadata using a copy of phone exercise
  definitions in a disposable simulator; no phone workout database was copied.
- `media-final-custom-library.png`: shared custom-library row, recovered pictures and dumbbell fallback.
- `navigation-fixed-all-0.png` through `-2.png`, `navigation-fixed-return.png` and
  `navigation-fixed-single-session.png`: three Show All/back cycles plus a session/back cycle.

Validation:

- Simulator app and the new integration regression test bundle compile.
- The actual Foundation metadata resolver and mechanically extracted production importer
  matcher passed **173** identity, ambiguity, custom-field and alias-precedence assertions.
- XCTest execution was not repeated: the simulator host issue from the previous pass remains
  documented separately. A successful test-bundle build is not represented as a test run.
- Signed iPhone/Watch build passed. Final installation and app launch succeeded on Josh's
  iPhone. The phone custom-exercise file was copied back read-only and was byte-for-byte
  identical to the original after launch.
- Simulator fixtures were restored, light/default sizing restored, CACE shut down, and shared
  resources returned to WhereWolf. No commits/pushes, data merges or imported Health exports.

After this work the owner stopped the V2 direction and asked about OpenGym's current catalog
and still images. That follow-up is source research; no OpenGym catalog/media/code has been
integrated into liteweight. See `EXERCISE_CATALOG_AUDIT.md` for the source/license distinction.
