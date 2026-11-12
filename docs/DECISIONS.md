# liteweight decisions log

Calls made for the owner without his explicit sign-off on the detail. Newest first. Each entry says why, where it lives, and how to undo it. Once commits exist, each entry names its commit, so `git revert <sha>` undoes it.

Builds are installed with `~/.local/share/liteweight/tools/install-NN.sh`. Lane briefs and reports live in `~/.local/share/liteweight/lanes/ui/`.

**Checkpoint commit `1607275`** (2026-11-06) contains every entry below dated up to and including build 97. Those entries can't be reverted one by one with git. Use each entry's "Roll back" steps instead. Entries added after this checkpoint each get their own commit.

**Builds 107–111** (2026-11-08) landed in one commit, because they changed the same files. Reverting that commit undoes all five; to undo one entry, change its parts back by hand.

**Builds 118–119** (2026-11-09) landed in one commit for the same reason. Reverting it undoes both.

---

## 2026-11-12

### Header morph both ways, idle number boxes, Log Set without Watch rebuilds (build 135)
- **Asked:** "these 3 animate into the glass pill, but the hr and kcal don't? also none of them animate out! to the big position!" plus the build 134 request for smooth workout animations.
- **Decided:** heart rate and energy carry `summaryMorph` IDs in the header row and the pill (only when the pill shows that reading), and the header draws above the logger while it expands, so the numbers no longer rise from the pill hidden under the cards. Idle weight/reps/distance boxes in every set row and the open set's big fields draw as text until tapped (30–40 live text fields were re-measured on every layout); tapping mounts the real field with the same keyboard and select-all. Logging sets in the workout in progress no longer rebuilds the Watch's saved-workout library, and the Watch exercise picks are built off the main thread. Add Exercises gives its list at most 40 rows while it slides in and the rest 0.45 s later (not for search, filters or VoiceOver).
- **Where:** `liteweight/UI/Workout/CurrentWorkoutView.swift`, `liteweight/WatchConnectivity/WatchConnectionManager.swift`, `liteweight/UI/Exercises/AddExercisesSheet.swift`.
- **Roll back:** revert this build's commit.

### Workout animations: the logger stops re-laying out everything (build 134)
- **Asked:** "can you please optimize every animation during the workout itself? like coreanimation if need be? 120 fps? smooth? the animation of opening/closing the active set, timer rolling in, modals coming in, everything?"
- **Found:** a DEBUG frame meter and animation tour (commit 56fb80a) showed 150–640 ms stalls on almost every logger animation. The logger was one ~3,900-line view: any state change, even a sheet flag, re-evaluated and re-measured every exercise card, set row and text field. A fresh swipe binding made every set row re-evaluate about 2,000 times in two short tours. Idle UIKit text fields (one per exercise) were re-measured and updated on nearly every layout.
- **Decided:** exercise cards and set rows are `Equatable` behind a stable `LoggerActions` relay with per-card snapshots; the open swipe is a plain value; idle text boxes draw as text until tapped; geometry state only publishes real changes; Add Set and swipe delete save after their animation instead of inside it. The rest ring and Finish confetti moved to Core Animation. Add Exercises caches its prepared catalog across opens and prepares it off the main thread.
- **Result (simulator, 60 Hz, worst frame before → after):** header collapse 316 → 100 ms, header expand 320 → 120 ms, scroll to next exercise 353 → 105 ms, scroll to top 227 → 103 ms, rest strip removal 297 → 85 ms, unlog 216 → 164 ms. Sheets: an empty control sheet costs ~300 ms in this simulator; closing any sheet now costs the same as the control, and opening Rest, RPE, Finish and Add Exercises costs 100–450 ms more than it (next: Add Exercises' first list frame, Finish's arrival work, Log Set).
- **Where:** `liteweight/UI/Workout/CurrentWorkoutView.swift`, `liteweight/UI/SwiftUISupport.swift` (`LiteweightRestRing`), `liteweight/UI/Components/LiteweightConfettiView.swift`, `liteweight/UI/Exercises/AddExercisesSheet.swift`, DESIGN_SYSTEM §11.
- **Roll back:** revert this build's commit.

### Home sections no longer clip at rounded corners (build 133)
- **Why:** the owner saw rounded clipping at the top left of Muscle Week and on the "D" of "Dot size shows sets". Build 130 made the cards clear but kept `.insetGrouped`, which still clips each section's rows to rounded corners. The 8 pt top inset from build 130 only hid it on This Week.
- **What:** Home's `List` is `.grouped`, which has square, full-width sections. Rows set only vertical insets through `homeRowInsets` and keep the list's side margins, which match the large title; before iOS 26 they use 16 pt.
- **Where:** `liteweight/UI/Feed/FeedView.swift`, DESIGN_SYSTEM §15.2.
- **Roll back:** revert this build's commit.

### Nothing ticks unless it's counting (build 132)
- **Asked:** "This app needs to be promotion supporting and not hitch!" and "just want it 120fps with no hitching!"
- **Found:** the Workout tab summary still rolled elapsed digits, stopped set stopwatches ticked twice a second, and paused/finished rest controls kept timelines alive. Collapsed pills and tab accessories refreshed whole surfaces every second; a DEBUG metrics timer accumulated across appearances, and held confetti kept an animation timeline running.
- **Decided:** elapsed clocks tick plainly, with model-driven sets/volume retaining their rolls. Set stopwatches use start-aligned one-second timelines only while running; rest controls tick only while unpaused with time remaining. Pill/accessory timelines refresh elapsed text and current vitals/accessibility reads, with titles and aggregates outside the clock; DEBUG metrics polling cancels on disappear, and held confetti uses a static Canvas.
- **Also (build 132):** per-row data lookups got cheaper with identical results: `SetTrackingPreferences.load()` returns a cached merged snapshot until its content or watermark revision changes; `ExerciseStore` keeps the joined catalog and uuid indexes instead of concatenating and searching per lookup; `WeightUnit.format(weight:from:to:)` reuses locked measurement formatters per unit and locale. Formatters handed to callers stay new, because a copy of a cached formatter shares ICU state and crashed a concurrent test. Optimized simulator logger: idle 4% → 1–2% busy, scrolling 23%/24% → 22%/18% (down/up). 634/634 tests.
- **Roll back:** revert this entry's commit.

### The logger stops redrawing every second (build 131)
- **Asked:** "I quite like our current workout view, just want it 120fps with no hitching! like promotion and no stutters!"
- **Found:** with the logger open and untouched, the main thread was 44% busy (Home: 0%, logger collapsed: 2%), and scrolling was 39%/30% busy (down/up) in an optimized simulator build. `LiteweightMetricValue` rolled its digits on every value change, so the Duration clock's `ticks: true` couldn't stop a numeric-text animation every second, which kept SwiftUI's display link running. Every exercise card's "Rest 3:00" label also re-evaluated each second.
- **Decided:** `LiteweightMetricValue(animatesChanges:)`; the running clock passes false and ticks plainly. Only the exercise whose rest timer is running wraps its rest label in a one-second `TimelineView`. Idle went 44% → 4%, scrolling 39%/30% → 23%/24%. Rest countdowns still roll by design.
- **Roll back:** revert this entry's commit.

### Home without cards (build 130)
- **Asked:** "the part i like most actually is not having the hideous cards everywhere on the home screen! not being contained is better! can you make the home screen without them?"
- **Found:** every Home section sat in a white inset-grouped card, so the page read as a stack of equal boxes.
- **Decided:** Home keeps its inset-grouped List but clears every row and the scroll background onto `homeBackground`, removes section containers and their horizontal padding, aligns content to the title with zero horizontal row insets, and uses 28 pt section spacing with bold title2 headings and native internal separators. At non-accessibility sizes, centered 188 pt rings sit above three equal metric columns with colored labels/values and separate target lines; the unchanged day strip follows after 18 pt without a divider, while accessibility sizes keep their previous layout and metric style. Other screens, Home content and interactions stay unchanged; inner chips and controls remain, and chart halos match the page.
- **Roll back:** revert this entry's commit.

### The real segmented control, with a blue thumb (build 129)
- **Asked:** "the kg to lb is not a native slider? right? why aren't we doing things thatway? is it mandataoyr?" then "go back to real then?"
- **Found:** builds 127–128 drew a custom control to get a blue selection, which lost the native drag between segments, the Liquid Glass thumb and future system changes. The stock control only looked off because of its gray thumb and the large control size.
- **Decided:** `LiteweightSegmentedPicker` wraps the system segmented picker at regular size; `LiteweightSegmentedAppearance.apply()` at launch gives every segmented control an accent thumb with on-accent text. Call sites, haptics and accessibility labels are unchanged.
- **Roll back:** revert this entry's commit.

### Workout heart rate shows without a button (build 128)
- **Asked:** "Why is there a button for show heart rate, show by default!"
- **Found:** a workout's Heart Rate card waited behind a Show Heart Rate button until one workout had loaded data, so every workout asked again until then.
- **Decided:** the card always loads when a workout opens. Apple Health setup (welcome guide and Settings) now asks for heart rate and active energy with everything else; if it never did, the card asks once in context. A denied read or a workout without Health data hides the card. The Health usage text now names active calories.
- **Roll back:** revert this entry's commit.

### Weight Unit separator back under the title (build 128)
- **Asked:** a screenshot of Settings › General with "The line?": the separator under Weight Unit started at the switch, not under the title like the rows below.
- **Found:** build 127 put the separator alignment inside `LiteweightSegmentedPicker`, which is right only when the picker fills its row.
- **Decided:** the picker no longer sets the separator; the two rows it fills by itself (plate equipment, ring goals) set it at the call site.
- **Roll back:** revert this entry's commit.

### One segmented control and one stepper across the app (build 127)
- **Asked:** "i really dont think that fits the theme! can you please think deeply about this kinda stuff?" After approving the solid blue, switch-height thumb: "restyle eveyrthign to be uniform! over the entire app it is uniform i'm hoping?"
- **Found:** the large stock Weight Unit picker was taller than its row title, gray selection contradicted blue meaning selection, and stock segments and custom range pills left two selection looks across the app.
- **Decided:** every iPhone segmented control, including exercise ranges and rest presets, uses `LiteweightSegmentedPicker`: one 32 pt tertiary-fill capsule track, solid blue 28 pt thumb, on-accent selected text, equal-width segments and full 44 pt tap targets. Remove the soft style. The thumb slides with matched geometry and the Reduce Motion-aware snappy token; unmatched values show no thumb. The component owns tap-only, settings-guarded haptics and a native accessibility picker. Weight Unit keeps its 104 pt standard-size width; equipment keeps a menu at accessibility sizes. Every system stepper becomes `LiteweightStepper`, using the logger's 40 pt round −/+ buttons in 44 pt targets, range clamping, disabled bounds/nil actions, hold-to-repeat, guarded step haptics and a native accessibility stepper. Labels stack above the buttons at accessibility sizes; label-hidden layouts remain available. The logger's own buttons stay unchanged. Native segmented styling and `Stepper` remain only in the two components' accessibility representations.
- **Roll back:** revert this entry's commit.

## 2026-11-11

### History scrolls without hitches (build 126)
- **Asked:** "Scrolling in history has massive jitters! This app needs to be promotion supporting and not hitch!"
- **Causes:** each Canvas draw created a renderer with an empty SVG path cache; display-only figures built interactive, tooltip and accessibility overlays, including another full path parse; History rows faulted Core Data exercise/set relationships for trophy counts and routine/plan relationships for titles, then scanned the catalog. RenderBox redrew two figure Canvases per row as rows scrolled in (13–16% of main-thread time in the simulator).
- **Decided:** share a locked, bounded path cache process-wide with keys containing the full SVG path and transform. Add `BodyView.decorative()` for Canvas-only rendering at all four display-only call sites, retaining their existing accessibility and hit-testing modifiers. Compute per-session trophy counts in the background history snapshot, persist them in cache version 2, and use snapshot display titles with the live workout title for renames. History and Last Workout figures render once per highlight set, scheme and contrast into a cached bitmap. Drawing math, SVG data and appearance stay unchanged; animated, pulse and zoom bodies keep their existing behavior. ProMotion is already enabled.
- **Roll back:** revert this entry's commit.

## 2026-11-09

### Watch: wheel scrolls the page after tapping a tile off mid-turn (build 125)
- **Asked:** "i press on lbs to change it, i scroll from like 245-265. then i press it again. Try scrolling to get to settings, NOTHING happens!"
- **Cause:** tapping the selected tile off rebuilt the ScrollView while wheel events were still arriving, so watchOS never gave the new page the wheel. The same sequence was reproduced in the Ultra simulator with real wheel input.
- **Decided:** clear the tile highlight immediately, but keep its Crown focus and rotation range until the wheel has been quiet for 0.3 s. Each Crown value change restarts the cancellable timer; only then does the existing page hand-back rebuild run. A new selection cancels settling; all other editing exits still release immediately and cancel any timer. Touch scrolling stays available during settling. No visual or layout change.
- **Roll back:** revert this entry's commit.

### Newer of plan weight and last lift fills the set (build 124)
- **Asked:** "the workout weight isn't a hard and fast rule, right? I'd prefer most recent workout ... Because I can set the weight but if i do a workout with 5 lbs over! that should inform and fill."
- **Decided:** a typed plan weight yields to the matching warm-up or working set from the latest finished workout (including imports) when that workout ended after the plan weight's last edit. Match the ordinal within that kind, falling back to its last set. Plans without a recorded edit time follow history. iPhone and Watch share the rule; blank plan weights are unchanged. Reps, duration, distance and tags are unchanged. Edit times stay local and outside backups.
- **Roll back:** revert this entry's commit.

### Saved workout editor matches the logger; Add Set fixed (build 123)
- **Asked:** "the saved workout creator needs an overhaul! should match the real workout player kind of in style! And right now I can't even add set!" The owner approved the simulator screenshots ("looks good! implement!").
- **Cause of the bug:** each exercise section was handed its set list as a value computed by the parent. Adding a set changes the exercise, not the observed workout, so the parent never redrew and the section kept showing the old list. The section now reads its sets from the exercise it observes.
- **Decided:** see DESIGN_SYSTEM §15.4.1. Judgment calls:
  - Set reordering moved from List drag handles to Move Up/Down in the set badge menu. There is no swipe-to-delete; Delete Set is in the same menu and the long-press menu.
  - The reps field uses the numbers-and-punctuation keyboard so ranges like "8-12" can be typed.
  - The rest line always reads "Rest 3:00", like the logger, including when it follows the workout default; the rest sheet still offers "Use Workout Default".
- **Roll back:** revert this entry's commit.

### Voice lines sit tight to their titles; Muscle Focus bars separate (build 122)
- **Asked:** on device, "these are spaced terribly??" (the Workout and Home voice lines), "move it above the search bar maybe?" (Exercises), and of Muscle Focus "the bars are dfiniely wrong? showing this week vs avg? maybe separtae them if you can't get ti right!"
- **Decided:**
  - Voice lines are an empty section's header on every tab, so they hug their text with 10 pt before the first card.
  - The owner suggested moving Exercises' line above the search bar. The iOS 26 navigation subtitle does that, but it shrinks the large title and truncates the line, so it stays below the search field. I told the owner.
  - Muscle Focus draws the average and this week as two separate same-height bars.
- **Roll back:** revert this entry's commit.

### Personality pass: brand plates, gold PRs, voice lines, muscle color on workouts (build 121)
- **Asked:** "our app looks so ugly and boring!", then after Round 11: "I want something like what we have, with PERSONALITY!" On Round 12 the owner disliked the gradients ("so AI"). They liked the labels (chips), confetti, per-exercise color, the PR label, and the plate mark with the voice line ("make sure the code labels that logo as temporary"). Through questions they chose voice lines on every tab, the gold streak chip (bigger), bigger This Week numbers, the PR moment while logging, a Watch-style start card, a Monday recap card and muscle-colored exercise lines. "keep the diagrams/pictures!!!": exercise pictures are never replaced.
- **Decided:** see DESIGN_SYSTEM §3.6. Judgment calls:
  - Voice-line fallbacks and the "busiest since" rule.
  - The recap shows for the week's first three days.
  - Confetti draws above the list for 2.5 s with no hit testing (behind opaque rows it wouldn't show).
  - The idle rest label takes the muscle color.
  - Two sets in one workout can both show PR, since records compare with earlier workouts.
- **Roll back:** revert this entry's commit. The brand mark and plate colors are marked TEMPORARY in code.

### Watch no longer opens Finish by itself (build 120)
- **Asked:** "having no sets left automatically shows finish workout screen on the watch? doesn't entirel make sense, right?"
- **Found:** after the last set's rest, or its RPE when no rest followed, `WatchNavigation` pushed Finish once per set list. The Now page already had an end state, "Every set is logged" with a Finish button, so the push only took the choice away. DESIGN_SYSTEM §22 also says the next step is surfaced "without navigation".
- **Decided:**
  - The flow returns to Now, which offers Finish.
  - A secondary Add Set adds one set to the last exercise with a logged set, the usual reason not to finish yet.
  - The `offeredFinishForSets` bookkeeping is gone.
- **Roll back:** revert this entry's commit.

### Apple Health page is informational; optional categories no longer warn (build 119)
- **Asked:** "Why's it say that? If it can't read if it has access? Maybe this page should just be informational! And show previously synced workouts too maybe?" The owner chose the category list, the latest 5 plus Show All, and removing Sync Past Workouts.
- **Found:** "Needs Review" appeared when any of the five save categories (workouts, weight, height, body fat, waist) was off or never asked, and that same state disabled Sync Past Workouts. So an optional body category blocked workout sync.
- **Decided:**
  - `HealthManager.accessState` follows workouts only: Connected, Not Saving Workouts, or Not Connected. The welcome guide's Health page uses the same state.
  - Settings lists each category's save status (Apple hides read status), with Ask for Missing Categories when one was never asked.
  - "Saved to Health" lists workouts whose export state is `exported` or `watch`, read from Core Data rather than HealthKit, plus a count of `pending` workouts.
  - The bulk sync button is gone. New workouts save on finish and pending ones retry on foreground, unlock and authorization. One workout can still be synced from its detail page. `updateHealthWorkouts` stays in HealthManager, unused.
- **Roll back:** revert this entry's commit.

### Muscle Focus bars share one height; calendars fit large text (build 118)
- **Asked:** "i dont like the filled and unfilled bars! one is wider! feels odd! fix!" and, of the Last 4 Weeks calendar clipping Friday and Saturday at accessibility sizes, "yes fix it!"
- **Decided:**
  - Both Muscle Focus bars are 10 pt: pale average behind, solid this week on top. When this week passes the average, a 2 pt gap in the solid bar marks the average's end, which a same-height bar would otherwise hide.
  - Home's Last 4 Weeks and the full Calendar measure their width at accessibility sizes and shrink the week to fit: cells go down to 36 pt and the numbers scale down. Below that they still scroll sideways, as before. Standard sizes are unchanged.
- **Roll back:** revert this entry's commit.

## 2026-11-08

### Muscle Focus draws both weeks; every editable Home card has its own edit (build 117)
- **Asked:** "maybe let's have 2 bars or a shaded bar inside of a filled bar? to indicate last week and this week in one go?", then "let the rings be modifiable individually? and the muscles to be modifiable individually! each card press and hold should have their own edit", "the home edit is primarily then for reordering and adding/removing!" and "maybe you can have an edit icon on each ... home widget". The owner chose bar inside a bar, the pale bar as the 4-week average, ring goals as Last Week or Custom, a range per muscle, the pencil plus hold menu, and Body rows.
- **Decided:**
  - Muscle Focus rows draw a wide pale average bar with a thin solid this-week bar on top; a neutral legend explains them by shape.
  - Rings, Muscle Focus, Body and Pinned Charts have a pencil by their title and "Edit [card]" in their hold menu. Edit Rings, Edit Muscle Focus and Edit Body are new sheets; Pinned Charts reuses Edit Charts, and its in-card Edit Pins row is gone.
  - Changing All Muscles resets every group's own range, as the approved design said. A group set back to the All Muscles range drops its own.
  - Customize Home is now titled Edit Home and no longer holds the set target. The new keys are in the settings backup.
- **Roll back:** revert this entry's commit.

### Muscle Focus shows this week; imported exercises get a muscle from their name; Watch library copies cleaned up (build 116)
- **Asked:** "i did 3 sets TODAY of arms and it's showing 2?" Checked against the phone's data: Arms was 8 sets in 28 days, so 2 a week, correct. The owner then chose "relable the muscle focus and add this week!", "fill in muscles probably yeah?" and "sure fix the leftover copy".
- **Decided:**
  - Muscle Focus has "Avg" and "This wk" columns; the caption says "Avg sets a week · last 4 weeks".
  - A custom exercise with no muscles and no catalog twin takes a primary muscle from its name (`ExerciseCatalogMetadata.inferredPrimaryMuscle`), in memory only, so imported "Seated Triceps Press" counts as Arms and "Back Extension (Machine)" as Back. Ordered rules keep "Leg Curl" out of biceps and "Hammer Strength" out of curls.
  - Cancelled Watch library and snapshot transfers delete their staged file (cancelling never reported finishing, so 2 MB copies piled up in tmp), and connecting sweeps any staged file no live transfer reads.
- **Roll back:** revert this entry's commit.

### Watch Set Options is a route; RPE scrub no longer wobbles or buzzes (build 115)
- **Asked:** "Navigating to a previous set and then options and pressing set type puts the page in the wrong place in the stack? Pressing back then takes me to the set type page?" and, of the iPhone RPE sheet, "Sliding the rpe slider audio sound bad, and the number jiggles oddly! Please animate it properly!"
- **Found:** the set editor's "…" pushed Set Options as a view destination, while Set Type and RPE are path routes. SwiftUI stacks path routes beneath view-pushed pages, so Back went to the wrong page. The RPE number changed width ("7" ↔ "7.5"), shifting the line, and each step restarted a spring; no sound plays there, so the "audio" was the per-step haptic running together on a fast scrub.
- **Decided:** Set Options is a `WatchRoute` (`setOptions`); the other view-pushed Watch pages push no routes, so none share the problem. The RPE number has a fixed-width slot, rolls in the drag direction, and both the sheet and `RPEGraph` animate with `fade`; haptics are capped at one per 60 ms.
- **Roll back:** revert this entry's commit.

### The logger summary morphs into the pill as you scroll (build 114)
- **Asked** (with a screenshot of the expanded summary): "Long ago you had the right idea! Scrolling down should show the compact info version! Top can show that! Can we have it morph instead of replace? Keep the arrow of course if someone genuinely wants to see the big".
- **Decided:** this reverses the "scrolling never changes modes" rule. The summary is big at the top and the pill once scrolled past 56 pt; it returns within 6 pt of the top. The pill scales in from the top while Duration, Volume and Sets fly into it (position-only matched geometry, so the pill's measured height and the scroll clearance never change mid-flight). Expanding with the chevron while scrolled keeps the big summary until the top; collapsing at the top pins the pill, as before. iOS 17 has no scroll-geometry callback, so it keeps the chevron only.
- **Roll back:** revert this entry's commit.

### Warm-ups and working sets fill separately; no RPE prompt after a warm-up (build 113)
- **Asked:** "warm up set was being informed by last working set? The lbs?", "working set shouldn't inform from working set!!" and "maybe no rpe dialog for working set? User can choose to add but no need". Read as warm-up sets throughout, since the first point is about warm-ups and RPE on a warm-up is the prompt that adds nothing; the owner can say if working sets were meant.
- **Decided:**
  - `SetValuePrefill.resolve` keeps one chain per kind: a warm-up follows the last warm-up in this workout, else last time's first warm-up; a working set follows the last working set, else last time's first working set. Before, every row copied the row just above it, so the first working set took the last warm-up's weight. iPhone and Watch share this resolver.
  - Logging a warm-up no longer opens RPE on iPhone or Watch; Add RPE stays on the set.
- **Roll back:** revert this entry's commit.

### Log Set closes smoothly; launch freeze fixed; Last Workout figure (build 112)
- **Asked:** "when completing set, set instant collapses, no animation! And the color comes in after the collapse! the blue backing highlight! please optimize that entire routine to make it better!" and "same thing for workout tab, last workout!" (the History muscle figure).
- **Found:** a 5× slow-motion recording (`-liteweightSlowMotion`, DEBUG) showed the editor gone in one frame: the save's redraw dropped the close animation. The blue then waited 340 ms plus a 0.3 s fade.
- **Decided:**
  - Log Set fades the editor's contents, closes its space, and turns the row blue as it lands, all on the row's own state. The save follows once the row has closed, then RPE (DESIGN_SYSTEM §11). The order the owner asked for in build 103, close then blue then RPE, is kept, now overlapping instead of waiting.
  - Launch could freeze while the logger was open: the Watch sync queue held the preference lock while writing defaults, which waits on SwiftUI, and the main thread, mid-render, waited on that lock. Defaults writes made inside the preference transaction now run after its outermost unlock (`SyncedPreferenceLock.afterUnlock`); in-memory values update at once.
  - The Workout tab's Last Workout row leads with the shared `LiteweightMuscleFigure`, like History.
- **Roll back:** revert this entry's commit.

### Muscle figure on History rows; every tip inline (build 111)
- **Asked** (relayed from the Aloud session, 12:56): "in history maybe instead of legs arms chest we should show a little muscle diagram?" and "the tip text is kinda broken and disjointed in places! Like the pencil edit button tip like goes inside of the button!" His screenshot showed the History tip bubble clipping its message.
- **Decided:**
  - History rows lead with a front-and-back muscle figure in place of the tile and group chips; the owner then asked for the same on the Workout tab's Last Workout row (`LiteweightMuscleFigure`, shared). Each muscle takes its group's color (solid for primary movers, faint for helpers), so the figure matches the tile and the calendar. Accessibility sizes keep the chips, which stay readable.
  - Every TipKit bubble became an inline tip: History and Home get a tip section at the top of the list, and Log Set and Pin to Home get a tip in the layout beside the control. The bubble helper `liteweightPopoverTip` is gone.
- **Roll back:** revert this entry's commit.

### Welcome guide and first-use tips (build 110)
- **Asked:** "Can we also please add a tutorial/guide to the beginning of the app? Guiding the user through its usage?" The owner approved every part of the proposal (claude.ai/artifact/ViXqmAnnwVropAvzdfteUd), G1–G8 and T1–T7, with no notes.
- **Decided (details the proposal left open):**
  - Existing users are anyone with a completed workout. They see the welcome once after updating, with Welcome, Apple Health (only if not yet connected) and Apple Watch (only if paired).
  - Starter plans use these catalog exercises, looked up by their stable IDs because the store shows display titles that can differ (one that doesn't resolve is skipped):
    - Full Body A: Squat: Barbell, Bench Press: Barbell, Row: Barbell (Bent Over), Plank.
    - Full Body B: Deadlift: Barbell, Overhead Press: Barbell, Pulldown (Wide Grip), Lunges: Dumbbell.
    - Upper / Lower and Push / Pull / Legs are listed in `StarterPlan.all`.
    - Sets are 3 × 8–12; Plank is 3 × 45 s.
  - Hevy and backup files picked during the welcome open after it closes, through the existing import and restore paths, so their progress and confirmation sheets aren't hidden.
  - T1 (Most Rested) is inline inside the card, pointing down at Start, because a bubble anchored in that List row never presented in the simulator.
  - T3 (rest) is inline under the rest strip instead of a bubble, because the RPE sheet can be up right after Log Set. T7 (Watch) is a one-time sheet, because watchOS has no tip bubbles and the Now page has no room.
  - The Watch keeps its own tip record. Show Tips Again resets the iPhone's tips only.
- **Roll back:** revert this entry's commit; remove the `welcome.completedVersion` and `tips.generation` defaults if needed.

### Polish Review: muscle colors, zoom, swipes, one main button, quieter Settings (build 110)
- **Asked:** the owner approved every fix on the Polish Review page (claude.ai/artifact/FKRMD8i8i7rXcASP45XHdc) and picked color option C, muscle colors, with no notes.
- **Decided (details the review left open):**
  - Muscle palette in `LiteweightPalette.muscle(_:)` (DESIGN_SYSTEM §3.5). It reverses the §3.2 rule that muscles are never color-coded. Chips and tiles use Home's names (abdominals is "Core"); tiles show the initial, and Core shows "Co" because Chest has "C".
  - History rows trade the exercise-names line for up to three muscle chips. The names come back when no exercise has a colored group.
  - History Delete has no confirmation dialog. The row hides and an Undo toast shows for 5 s; the workout and its Apple Health copy are deleted when the toast expires. `LiteweightToast` gained an optional action, and only an action toast takes touches, only on its capsule.
  - "Pin to Home" sits on an exercise's chart for 1RM and Volume. Top weight has no Home chart type, so it gets no pin.
  - The empty-workout button goes gray only while Most Rested is showing.
  - Rolling numbers come from `LiteweightMetricValue` and `LiteweightWorkoutMetricLine`, so everything built on them rolls. No tick haptic for numbers that change without a touch.
  - Logger (L1): the "Watch offline · changes queued" line shows only after this workout's phone changes have waited 30 s for a Watch that's part of the workout. Otherwise a small Watch symbol in the summary shows the connection. Live heart rate and energy still show on that line while the Watch is in reach.
  - A finished workout (D1) uses the logger's own summary components (`WorkoutSummaryMetric`, `WorkoutSummaryMuscleFigure`).
  - Launch (P4): Home, History and the Workout tab start from `TrainingHistoryCache`, the last history read saved as versioned JSON. It's discarded if any workout in it is gone, and exercise bests wait for the first refresh. About 0.4 KB per workout.
  - Settings (S1–S4): connection pages show a badge plus one detail line (`SettingsConnectionHeader(detail:)`). Check rows appear only when something fails, with a footer saying what to do. Watch Refresh is a toolbar button, and Watch reachability (Standby) no longer shows on the page. The Health badge names Needs Review and Unavailable. About has one unheaded Links group. Support no longer repeats About. Settings and plate calculator footers are one short line or none.
- **Roll back:** revert this entry's commit.

### Tab titles scroll away; search bars sit on a translucent edge; Units on the Settings list (build 109)
- **Asked:** "no need to keep header, or header background, right? cant we just have pencil icon for edit, and search bar with translucent back?" and, of the one-row Units page, "too small! … things like that shouldn't be there?"
- **Decided:**
  - Home, Workout and Settings use `liteweightTabTitle` (iOS 26+): the large title sits in the toolbar row beside the buttons and fades out once the list scrolls, so only the floating buttons stay. No inline title or bar band. iOS 17–25 keep the inline-large system title.
  - Home's Edit is a pencil glass button.
  - History, Exercises and the add-exercise picker go back to the soft (translucent) scroll edge under pinned search. This reverses the build 98 entry below.
  - The kg | lb switch moved onto the Settings list as a full-size row ("Weight Unit"); the Units page is gone. Appearance keeps its page because it has a real preview picker.
- **Roll back:** revert this entry's commit.

## 2026-11-07

### Renamed to liteweight
- **Asked:** the owner chose the final name **liteweight**, all lowercase wherever people see it.
- **Decided:**
  - Code uses the `Liteweight` prefix, lowercase `liteweight` helpers, and matching project, target and resource paths.
  - The app ID is `me.joshpatra.liteweight`; existing data moves by backup and restore into the new app's container.
  - The “Built on Iron” upstream credit stays in About and the project credits stay in README.
  - Feedback goes to `liteweight@joshpatra.me`.
  - New backups use `.liteweightbackup`; old backups still restore, including their saved settings.
- **Roll back:** restore the pre-rename files from a deliberate owner-approved snapshot; this lane is uncommitted. The new app ID has a separate container, so move data with backup and restore when switching identities.

## 2026-11-06

### Search moves into the title row; one filter icon (build 101)
- **Asked:** "when scrolling down, remove the exercises label and move the search bar in" and "always just have the icons". The owner picked one filter icon, on Exercises, the add-exercise picker and History, and Apple's own search placement over a custom row.
- **Decided:**
  - Exercises and History use iOS's `.toolbarPrincipal` search placement (iOS 26+, via `titleRowSearchable`). Search sits under the title at the top and takes over the title row once scrolled. While it's up there, iOS hides the filter and + buttons; scrolling up or tapping the status bar brings them back.
  - The two labeled filter buttons became one filter icon next to + (Muscle, Equipment, and Clear Filters when a filter is on). When a filter is on, the icon fills blue, removable chips ("Chest ×") show at the top of the list, and the search box names the filter ("Search Chest"), so a filter is visible even while scrolled.
  - **My call:** the add-exercise picker keeps its pinned search under the title. In that sheet, iOS also hid Cancel and Add once search moved up. The picker still gets the filter icon (in its bottom bar), the chips and the prompt.
- **Roll back:** `git revert` this entry's commit. It touches only ExerciseMuscleGroupsView, AddExercisesSheet, HistoryView, SwiftUISupport and DESIGN_SYSTEM.

### Previous Sessions rows use the exercise page's set chips (build 100)
- **Found in the overnight sweep at Extra Large text:** a past workout's exercise page listed each earlier session as one comma-joined line ("115 lb × 4, 120 lb × 5, …") limited to two lines. It broke mid-set ("× 8" alone on a line) and cut off long sessions.
- **Decided:** those rows now show the same wrapping set chips ("115×4") as the exercise page's History, through one shared `ExerciseSetChip`. Record sets get the record tint and warm-ups the warm-up tint, as there. The date, the session total and the note line are unchanged. VoiceOver reads each row as one sentence.
- **Roll back:** `git revert` this entry's commit (it touches only ExerciseHistoryView and WorkoutExerciseDetailView).

### Exercise pages show their name in the bar once scrolled (build 99)
- **Found in the overnight sweep at Extra Large text:** a scrolled exercise page, and a past workout's exercise page, had an empty navigation bar. Both also set an empty screen title, so VoiceOver had no page name. A finished workout's page already fades its name into the bar once its header scrolls away.
- **Decided:** both exercise pages copy the workout page's behavior through one shared modifier, `ListHeaderScrollTitleModifier` in `SwiftUISupport.swift`. The big header is unchanged; the bar shows a one-line copy once it's gone. Before iOS 18 the bar title just stays visible.
- **Roll back:** `git revert` this entry's commit (it touches only ExerciseDetailView, WorkoutExerciseDetailView and SwiftUISupport).

### Pinned search uses a hard top scroll edge (build 98; reversed in build 109)
- **Found in the overnight sweep:** with search pinned, scrolled rows read through the field and bar on Exercises, History and the add-exercise picker, in light and dark.
- **Decided:**
  - On iOS 26 and later, the lists use `.scrollEdgeEffectStyle(.hard, for: .top)`; iOS 16–25 get a visible navigation bar background.
  - The Exercises filter section loses its extra top spacing, to match History.
- **Roll back:** `git revert` this entry's commit (it touches only ExerciseMuscleGroupsView, HistoryView and AddExercisesSheet).

### A past workout's exercise page opens read-only (build 98)
- **Why:** the owner approved read-only-by-default for finished workouts (audit D1). The exercise page reached from a finished workout was still the live logger, so it was inconsistent.
- **Decided:**
  - Read rows match the workout page's ("1  115 lb × 4"). Edit/Done switches to the unchanged editor. Notes show as plain text.
  - Previous Sessions uses short list dates ("Thu, Oct 29").
- **Roll back:** `git revert` this entry's commit (it touches only WorkoutExerciseDetailView).

### WorkoutDataKit compiles optimized in Debug (build 97)
- **Decided:** set `SWIFT_OPTIMIZATION_LEVEL = "-O"` for the WorkoutDataKit target's Debug configuration only.
- **Why:**
  - The new performance test measured about 1.1 s per full-catalog search in Debug: 36.7 s for 32 searches.
  - The owner's phone runs Debug builds, and unoptimized Swift string code was the bottleneck.
  - Search logic and ranking are unchanged. ENABLE_TESTABILITY stays on, so `@testable import WorkoutDataKit` still works.
- **Trade-off:** stepping through WorkoutDataKit in the debugger is less precise.
- **Roll back:** set that one setting back to `"-Onone"` (WorkoutDataKit Debug, in `liteweight.xcodeproj/project.pbxproj`).

### Exercise search runs off the main thread and stays pinned at the top (build 97)
- **Asked:** "search is super laggy" and "search should stay atop!"
- **Decided:**
  - Search waits for a 120 ms typing pause, then ranks results in the background from cached, pre-sorted lists.
  - The list no longer animates while typing.
  - Thumbnails decode in the background.
  - The search field is pinned under the title on Exercises, History and the add-exercise picker (`.navigationBarDrawer(displayMode: .always)`).
- **Why:** each keystroke re-sorted about 5,749 exercises on the main thread, and the list animated a diff of thousands of rows.
- **Where:** `ExerciseMuscleGroupsView.swift`, `AddExercisesSheet.swift`, `ExercisesView.swift` (thumbnails), `HistoryView.swift`, `WorkoutDataKit/Model/ExerciseSearch.swift`.
- **Roll back:**
  - Placement only: remove the `placement:` argument from the three `.searchable` calls.
  - Performance: revert the lane SR files.

### Watch redesign, round 2 (build 96)
- **Asked:** "do a full redesign", no scroll-wheel editing on a scrolling page, and consistent radii.
- **Decided:**
  - One shape per role: rows and cards use `watchPlatter()`; navigation and secondary actions are glass capsules; one blue primary capsule per page.
  - Home Settings became a capsule.
  - The set editor became one screen, with a new Set Options page behind "⋯".
  - Bar Weight became one screen with preset capsules.
  - Option icons use one style, a solid role-color circle with a white symbol.
  - Row values are secondary text; accent marks only tappable items.
- **Where:** `liteweight Watch Extension/UI/ContentView.swift`, `WorkoutSessionView.swift`, `WatchDesign.swift`, `LiteweightApp.swift` (demo routes).
- **Roll back:** revert lanes W2A and W2B. A pre-lane copy of the Watch UI files is at `~/.local/share/liteweight/pre-watch-audit/files.tar`, but it predates rounds 1 and 2.

### Watch plate calculator layout (build 96)
- **Asked:** "diagram front and center? weight small? idk!"
- **Decided:**
  - One screen, with the scroll wheel always editing the weight.
  - The total sits small on top, and the full barbell is drawn large in the middle.
  - Each scroll step changes the weight by the smallest loadable increment.
  - Setup moved to its own page behind a toolbar button.
  - Plates are 12% of their height wide (8% for small plates).
- **Where:** `WatchPlateCalculatorView` in `WorkoutSessionView.swift`.

### Watch clock margins restored (build 95)
- **Decided:** reverted `WatchVitalsInset` margins to 34/22 pt (below 180 pt). Lanes had trimmed them to 32/18, which hid the clock on the owner's Ultra.
- **Rule:** don't change them without a device check.

## 2026-11-05

### Workout tab: "Most Rested" card (design A; build 93)
- **Owner approved** design A and said "don't shrink the start workout button".
- **Decided the logic:**
  - Rest per muscle group comes from the same data as Home's Muscle Week.
  - The pick is the saved workout whose least-rested muscle has rested longest; ties go to the one done longest ago.
  - Tags turn green at 2 or more days, orange under 2 days, and grey for "new".
  - Tags use broad groups ("Arms"), not "Biceps", to match Home.
- **Roll back:** remove the card from `StartWorkoutView.swift` (lane WT).

### Start Workout removed from Home (build 91+)
- **Owner note:** "Maybe not even have start workout on that page!"
- **Decided:** removed it entirely. The optional Next Workout card keeps its Start button, and the floating bar handles resume.

### Home defaults and cards (build 91+)
- Removed the date under the Home title, since the week range already shows it.
- Took Recent Training out of the default cards; saved layouts are unchanged.
- Merged Body Weight into Body; stored "bodyWeight" maps to "body".

### Prefill rule interpretation (build 93)
- **Owner rule:** a later set copies the previous set; the first set copies last time's; never done means empty.
- **Decided:** values the owner typed into a saved workout's targets count as typed and are kept. Warm-up sets copy last time's first warm-up.

### e1RM (build 92)
- **Asked:** count every set.
- **Decided:**
  - One formula, Epley, everywhere.
  - A 1-rep set counts as its exact weight.
  - Removed the "Count Sets Up To" setting; the stored key stays for backups.

### Exercise renaming (X3, build 93)
- **Approved** in the audit.
- **Decided:**
  - Only an allowlist of equipment words moves to the end: Barbell, EZ Bar, Dumbbell, Cable, Kettlebell, Band, Smith Machine, Trap Bar, Landmine.
  - Name collisions keep their original titles.
  - Siri suggestions match on the original title.
- **Roll back:** revert lane R1. U9's first attempt is saved at `~/.local/share/liteweight/lanes/ui/U9.patch`.

### Tab titles use inline-large display (build 93)
- **Asked:** "why are they wasting vertical space".
- **Decided:** `.toolbarTitleDisplayMode(.inlineLarge)` on all five tab roots. Detail pages are unchanged.
- **Roll back:** switch back to `.navigationBarTitleDisplayMode(.large)`.
