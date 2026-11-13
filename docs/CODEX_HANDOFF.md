# liteweight: handoff for a Codex agent (2026-11-12, after build 135)

Read this whole file before doing anything. It is the current state; `docs/HANDOFF.md` is older
history and is partly out of date. When the two disagree, this file wins.

## 0. In one paragraph

liteweight is Josh's SwiftUI strength-training app for iPhone and Apple Watch (Core Data model in
`WorkoutDataKit/`). You work on `main` in `/Users/joshp/Projects/liteweight` (remote `origin` =
`SoPat712/liteweight`). The last shipped build is **135** (commit `84a10ad`, plus DEBUG-only
`f072827`). It is installed on Josh's iPhone, pushed, and passed all 634 unit tests. The working
tree was clean when this was written. The current project is making every animation in the live
workout logger smooth (120 fps on ProMotion). Most of it is done; see §6 for what is left.

## 1. Hard rules (breaking any of these is worse than doing nothing)

1. **Commits:** Josh gave standing approval to commit and push finished, verified work to
   `origin main`. NEVER put any AI wording in commits: no `Co-Authored-By`, no "Generated with",
   no "Claude"/"Codex" lines, no session IDs. Never stash, reset, checkout, rebase, rewrite history
   or force-push. Never push anywhere but `origin`.
2. **Never touch `reference-material/`** (untracked on purpose; never add it).
3. **Apple Health:** only workouts completed in liteweight are exported. Imported workouts
   (`Workout.importSource != nil`) are never exported.
4. **No new package dependencies.** Every new Swift file must be registered in
   `liteweight.xcodeproj/project.pbxproj` (in the right target).
5. **Design system:** use `LiteweightTheme` color roles, `Font.liteweightMetric` and
   `LiteweightMotion` tokens. No hard-coded colors, no gradients, no rounded font design.
   Read `docs/DESIGN_SYSTEM.md` before any UI work.
6. **Preserve** persistence, Watch sync, Live Activity and accessibility behavior whenever you
   change visuals or performance.
7. **Phones:** Josh's iPhone is `00008150-001914903E69401C`. **NEVER install on Keya's iPhone
   `00008150-001625193C21401C`.** Never use `devicectl … --remove-existing-content`. Never play
   audio out loud on devices. **Never seed sample data on the real phone** (the `-liteweightSeed…`
   flags are simulator-only).
8. **Never print, copy, commit or upload** the App Store Connect `.p8` key or any env file contents.
9. **Exercise pictures:** don't view exercise art; always launch with `-liteweightHideExerciseArt`
   for screenshots. Never remove exercise pictures from the app.
10. **Design taste:** Josh approves visual designs before they ship. For anything that changes how
    a screen looks (not just performance), describe or mock it and ask him first. Say
    "scroll wheel", never "Crown", when talking to him.
11. **Shared Mac:** other agents (WhereWolf, Songbird, Aloud, others) share this Mac, its CPU and
    ONE simulator. Follow §3 exactly. Never boot a second simulator, never quit Simulator, never
    stop other agents' processes.

## 2. Docs to read

- `AGENTS.md`: repo rules (short).
- `docs/DESIGN_SYSTEM.md`: colors, type, spacing, components, motion (§11 has the logger
  rendering rules added in builds 134–135), copy.
- `docs/DECISIONS.md`: one entry per build, newest first. Add one for every build you ship.
- `docs/DESIGN_BACKLOG.md` §0.3: build commands (older; the scripts below are what's used now).

## 3. Building, testing, simulator: the shared-resource rules

Everything heavy goes through the coordinator so agents don't overload the Mac:

```
python3 ~/.local/share/agent-coord/coord.py status
python3 ~/.local/share/agent-coord/coord.py inbox liteweight        # read before every claim
python3 ~/.local/share/agent-coord/coord.py run compiler liteweight "liteweight: <what>, ~N min" -- <command>
python3 ~/.local/share/agent-coord/coord.py run simulator liteweight "<what>" -- <command>   # sim-only work
python3 ~/.local/share/agent-coord/coord.py run check liteweight "<what>" -- <command>       # tests (both slots)
python3 ~/.local/share/agent-coord/coord.py message WhereWolf "liteweight: <done/released>"
```

- Exit code **73 = BUSY**: wait ~20–30 s and retry. It is never success. The queue is first come,
  first served. Every script below already has a retry loop.
- Builds: `nice -n 10 xcodebuild -jobs 1` or `-jobs 2` inside
  `/Users/joshp/Projects/WhereWolf/ci_scripts/resource_guard.py` (the scripts do this).
  Always pass `-clonedSourcePackagesDirPath ~/.local/share/liteweight/spm
  -disableAutomaticPackageResolution`.
- **The only simulator:** WhereWolf Regression `42FA2C2F-F66C-41DB-A33C-A018165BB0D7`
  (iPhone, iOS 26). Keep it booted. Reset anything you change (`xcrun simctl ui <id> appearance
  light`, `content_size large`) when you're done.
- **Unit tests:** `xcodebuild test` hangs here. Use the frozen-commit test script (below), which
  uses the standalone runner and must NOT run inside the resource guard (the guard pauses the
  test app and launches time out).

### Scripts (all in `~/.local/share/liteweight/`)

| Purpose | Command |
|---|---|
| Optimized simulator build of the working tree (for perf work) | sync, then build: `cd /Users/joshp/Projects/liteweight && { git ls-files; git ls-files --others --exclude-standard; } \| rsync -a --files-from=- . ~/.local/share/liteweight/perf-src/ && zsh ~/.local/share/liteweight/verify/lg-build.sh "<label>"` → app at `perf-dd/Build/Products/Debug-iphonesimulator/liteweight.app` |
| Animation timing tour (build + run + table) | `zsh ~/.local/share/liteweight/verify/fm.sh <TAG> 4` (syncs, builds, runs 4 repeats, prints per-step frames) |
| Device build of ONE commit (frozen copy, so the tree can keep changing) | `zsh ~/.local/share/liteweight/tools/device-build-commit.sh <commit> "liteweight: build N device build, capped 60%, -jobs 2"` |
| Install that build on Josh's iPhone | `zsh ~/.local/share/liteweight/tools/phone-install.sh` (Josh's phone only; prints the installed build number) |
| Full unit tests of ONE commit (634 tests, ~6 min + build) | `zsh ~/.local/share/liteweight/tools/test-commit.sh <commit> "build N"` → prints `TESTS {'planned': 634, 'tests': 634, 'failures': 0, ...}` |
| Simulator touch input (no idb) | `~/.local/share/liteweight/crown/simhid <sim-id> tap <x_ratio> <y_ratio>` / `drag <x> <y0> <y1>` / `hdrag <y> <x0> <x1>` (ratios of the screen, 0–1) |
| Screenshot | `xcrun simctl io <sim-id> screenshot --type=png <file>` |

Coordinate taps go stale when the scroll position differs between launches. Tap at the
unscrolled launch position whenever you can.

### Release order (Josh's explicit preference)

1. Check the change in the simulator (screenshots: light, dark, `content_size accessibility-medium`;
   pixel-compare with `compare -metric AE -fuzz 2% before.png after.png diff.png` when the look
   must not change).
2. Bump `CURRENT_PROJECT_VERSION` in `liteweight.xcodeproj/project.pbxproj` (it appears 12 times;
   `sed -i '' 's/CURRENT_PROJECT_VERSION = 135;/CURRENT_PROJECT_VERSION = 136;/g'`).
3. Add a `docs/DECISIONS.md` entry (Asked / Decided / Where / Roll back) under today's date.
4. Commit (`perf: build 136 — <one line>` / `fix: …` / `feat: …`, a plain-English body, NO AI lines).
5. Device build of that commit → **install on the phone first** → `git push origin main`.
   Josh: "install on my phone first then run tests! I usually offer advice shortly after getting
   it on my phone!"
6. Then run `test-commit.sh` on that commit. If anything fails, fix it in the next build.

**Phone access:** the phone is shared through a Claude session named Songbird. Songbird says
install-only on Josh's iPhone needs no grant, just an announcement, but Josh hasn't confirmed
that himself. You can't message Songbird directly, so **tell Josh before you install** and after
it's done. Launching the app on the phone, tracing, recording or copying files from it always
needs Josh's OK. Clean up after yourself: `device-build-commit.sh` deletes its `rel-src` copy;
don't leave builds, traces or big files in `/tmp`.

## 4. Useful DEBUG launch flags (simulator only)

Launch: `xcrun simctl launch --terminate-running-process 42FA2C2F-F66C-41DB-A33C-A018165BB0D7 me.joshpatra.liteweight <flags>`

- Base set for screenshots: `-liteweightSkipHealthAuthorization -liteweightHideExerciseArt -liteweightSeedSampleData -liteweightSkipWelcome`
- `-liteweightSeedActiveWorkout`: opens the live logger with a seeded workout.
- `-liteweightInspectHome`, `-liteweightInspectHistory`, `-liteweightInspectSettings`,
  `-liteweightInspectWorkoutTab`, `-liteweightInspectAddExercises`, `-liteweightInspectFinishWorkout`,
  `-liteweightInspectCollapsedSummary`, `-liteweightHoldConfetti` (and more `-liteweightInspect…`,
  grep for them).
- `-home.cards rings,muscleWeek,pace,bars,calendar,recent,muscles,body,pinned,records,nextWorkout,trainingTrend,muscleLoad`: shows every Home card.
- `-liteweightSlowMotion`: every `LiteweightMotion` token 5× slower.
- `-liteweightSeedWatchVitals`: fake Watch heart rate 128 / 212 kcal in the logger header.
- Frame meter + tour: `-liteweightFrameMeter -liteweightFrameMeterReset -liteweightAnimationTour
  -liteweightAnimationTourRepeats N`, plus `-liteweightAnimationTourSheetsOnly`,
  `-liteweightAnimationTourSetsOnly`, `-liteweightAnimationTourSteps a,b`.
  Writes `Documents/frame-meter.jsonl` in the app container and prints `FRAMEMETER {json}` lines;
  `verify/fm-agg.py <jsonl>` makes the table.
- `-liteweightPrintRowChanges`: SwiftUI `_printChanges()` for every set row and exercise card
  (shows WHY they redraw).

## 5. What happened today (builds 128–135), most recent first

- **135** (`84a10ad`): header ↔ pill morph works both ways, and heart rate/kcal fly too
  (`summaryMorph` IDs `heartRate`/`energy`; the header draws above the logger while it expands).
  Idle weight/reps/distance boxes in every set row and the open set's big fields are `Text` until
  tapped (they used to be 30–40 live UITextFields re-measured on every layout). Logging sets no
  longer rebuilds the Watch's saved-workout library (`WatchConnectionManager.affectsLibrary`), and
  the Watch exercise picks are built off the main thread. Add Exercises lists ≤ 40 rows while it
  slides in.
- **134** (`28b731e`): the big logger performance rewrite. `CurrentWorkoutView` used to rebuild
  and re-measure every exercise card and set row on any state change. Now:
  `LoggerExerciseCard` and `InlineWorkoutSetRow` are `Equatable` + `.equatable()`; all callbacks
  go through one stable `LoggerActions` relay (`@dynamicMemberLookup`, refreshed every body
  evaluation, `reset()` on disappear to break a retain cycle); per-card snapshots
  (`LoggerExerciseInput`, `LoggerExerciseSnapshot`); `LoggerTextField` (idle text for the workout
  title, workout notes and exercise notes); rest ring is a `CAShapeLayer` (`LiteweightRestRing`
  in `SwiftUISupport.swift`, takes `duration:`); Finish confetti is `LiteweightConfettiView`
  (`liteweight/UI/Components/`, CALayer keyframes); Add Exercises caches its prepared catalog
  (`AddExerciseCatalogCache`) and refreshes "Today/Yesterday" captions at midnight.
- `56fb80a` / `f072827`: DEBUG frame meter (`liteweight/_debug/LiteweightFrameMeter.swift`) and
  the logger animation tour (inside `CurrentWorkoutView.swift`).
- **133** (`ecd50f4`): Home uses a `.grouped` List (not `.insetGrouped`), so sections are no
  longer clipped to rounded corners; rows set only vertical insets (`homeRowInsets`).
- **132**: nothing ticks unless it's counting (clocks don't roll their digits; timelines only
  while counting); cheaper per-row lookups.
- **131**: logger idle redraw fix. **130**: Home without cards. **129**: native segmented
  control with a blue thumb. **128**: Weight Unit separator fix; workout heart rate shows without
  a button.

### Logger performance rules (do not regress these)

- Never pass a set row or card a freshly built `Binding` or anything that changes on every
  update. A new `Binding(get:set:)` compares unequal every time and re-evaluated every row
  ~2,000 times per short tour. Pass plain values; write through `LoggerActions`.
- Never put an always-live `TextField` in a row. Use the idle-text pattern (`LoggerTextField`,
  the set row's number boxes): `Text` until tapped, then the real field focused, back to `Text`
  on focus loss.
- Don't write geometry-derived `@State` during animations unless the value really changed
  (round and compare first).
- Don't save Core Data inside `withAnimation`. Mutate inside, save after.
- Keep the logger's eager `VStack` (a `LazyVStack` broke scroll targets, rest-strip anchoring and
  keyboard focus before). Keep every `.id(...)` scroll target.
- Measure with `fm.sh`. The tour includes an EMPTY control sheet (`emptySheetIn/Out`). In this
  simulator, an empty sheet alone costs ~150–300 ms because the simulator renders sheets in
  software. Compare sheet steps against it, not against 16.7 ms.

### Numbers (simulator at 60 Hz, worst frame in ms; build 135 run had a lightly loaded Mac)

| Step | Baseline (132) | Build 135 |
|---|---|---|
| headerCollapse | 316 | 69 |
| headerExpand | 320 | 82 |
| scrollNextExercise | 353 | 82 |
| scrollTop | 227 | 70 |
| restStripOut | 297 | 77 |
| unlog | 216 | 98 |
| logSet | 147 | 151 (avg stall 207 → 100) |
| emptySheetIn / Out (control) | n/a | 160 / 144 |
| rpeSheetIn / restSheetIn | 550 / 530 | 312 / 309 |
| finishIn | 636 | 462 |
| addExercisesIn | (not measured) | 699 |
| sheet closes | 263–344 | 159–184 (≈ control) |

## 6. Open work, in priority order

1. **Wait for Josh's feedback on build 135 in a real workout.** He may report specific
   animations. Fix what he names first.
2. **Log Set worst frame (~150 ms in sim).** Profile with the sets-only tour:
   `verify/fm-sets-inner.sh <TAG>` under `coord.py run simulator` (see how `fm.sh` and the
   `*-inner.sh` scripts are written), then
   `python3 ~/.local/share/liteweight/verify/fm-frame.py <sample.txt> "liteweight\]"` for app
   code and `verify/fm-callers.py` / `verify/fm-subtree.py` for who calls what. Known remaining
   cost before build 135: the open set editor's text fields (now idle text, re-measure), plus
   `WorkoutExercise.setTrackingType` / `trackedCompletedVolume` recomputed in the root body.
3. **Finish sheet arrival (~300 ms above the control).** App code is small; the cost is SwiftUI
   laying out the text-heavy recap during the slide-in (`ResolvedTextFilter`, stack layout).
   Ideas: show the recap's lower sections after the sheet lands; precompute the recap
   (`FinishWorkoutRecap`) before presenting. Don't change how it looks without asking Josh.
4. **RPE and Rest sheets (~150 ms above control).** RPE sizes itself to its content
   (`.presentationDetents([.height(contentHeight)])`); stabilize the height before presenting.
   The Rest sheet builds its ruler on open (`liteweight/UI/Workout/RestTimerView.swift`).
5. **Add Exercises open (~540 ms above control in sim)**: the main thread is 96% idle during it,
   so it's the simulator drawing a tall sheet over the scaled-back logger. Verify on the phone
   before spending more time on it.
6. **Questions Josh hasn't answered yet:** should the Home training calendar be all blue like the
   mockup (it keeps muscle colors now)? Should the gray "voice" line under the Home title go? Does
   History scroll smoothly on his phone now?
7. Shared task page (Josh's dashboard): https://claude.ai/artifact/DFHZikc9sbiqf7dEyCPBQJ. If
   you can't update it, tell Josh what changed instead.

## 7. Where things are in the code

- Live logger: `liteweight/UI/Workout/CurrentWorkoutView.swift` (~7,000 lines). Key types:
  `LoggerActions` (top), `LoggerTextField`, `CurrentWorkoutView` (root: top bar, session header,
  collapsed pill `collapsedWorkoutSummaryPill`, sheets), `LoggerExerciseCard` (one exercise),
  `InlineWorkoutSetRow` (one set; `measurementField`, focused editor, Log Set sequence
  `toggleCompletion()` / `closeEditorThenLog()`), `RPEPickerSheet`, `FinishPlateConfetti`,
  `WorkoutSessionProgressBar`. DEBUG tour: `runAnimationTourIfRequested`.
- Shared UI pieces: `liteweight/UI/SwiftUISupport.swift` (`LiteweightMetricValue`,
  `LiteweightRestRing`, segmented picker, steppers).
- Home: `liteweight/UI/Feed/FeedView.swift`, `liteweight/UI/Components/HomeWeekViews.swift`.
- Add Exercises: `liteweight/UI/Exercises/AddExercisesSheet.swift`.
- Watch sync: `liteweight/WatchConnectivity/WatchConnectionManager.swift`.
- Theme: `Shared/UI/SwiftUI/LiteweightStyle.swift`.

## 8. How Josh works

- He tests every build on his phone right away and replies with screenshots, often with red
  scribbles. Short messages, lots of typos; read for intent.
- He wants things to look Apple-native but with character, and he wants speed: ship small
  builds often rather than one big one.
- He dislikes: cards everywhere on Home (removed), stock controls that look off-theme (restyle
  the native control rather than rebuilding it), anything that stutters.
- When a screenshot is from a different app (for example the WhereWolf/Dawarich location app
  with Tracker/Trip/Insights tabs), it's not liteweight. Tell him and don't touch that repo.
- Explain what you found in plain words, then what you changed, then what's left. No jargon
  dumps.
