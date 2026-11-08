//
//  LiteweightTips.swift
//  liteweight
//
//  First-use tips (TipKit). Each appears once, beside the thing it explains, and
//  closes with ✕ or by using the feature. Tip IDs carry a generation number, so
//  Settings › Help › Show Tips Again brings every tip back at once.
//

import SwiftUI
import TipKit
import os.log

/// Shared state every tip's rules read.
struct LiteweightTipState {
    /// False while the welcome is up, so no tip opens behind it.
    @Parameter static var isReady: Bool = false
}

enum LiteweightTips {
    static let generationKey = "tips.generation"
    private(set) static var isConfigured = false

    static var generation: Int { UserDefaults.standard.integer(forKey: generationKey) }

    /// Screenshot runs, inspection screens and the unit-test host never see tips.
    static var isSuppressed: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-liteweightShowTips") { return false }
        #endif
        return WelcomeGuideController.isSuppressed
    }

    /// Call once at launch, before any tip is shown.
    static func configure() {
        guard !isConfigured, !isSuppressed else { return }
        #if DEBUG
        // Testing switches only take effect before configure.
        if ProcessInfo.processInfo.arguments.contains("-liteweightShowTips") { Tips.showAllTipsForTesting() }
        #endif
        do {
            try Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
            isConfigured = true
        } catch {
            os_log("Tips could not be configured: %@", type: .error, error.localizedDescription)
            return
        }
        // Nothing opens before the welcome has had its turn; the root view decides.
        LiteweightTipState.isReady = !WelcomeGuideController.isOutstanding
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-liteweightShowTips") {
            LiteweightTipState.isReady = true
        }
        #endif
    }

    static func setReady(_ ready: Bool) {
        guard isConfigured else { return }
        LiteweightTipState.isReady = ready
    }

    /// New IDs for every tip, so each shows again the next time its screen appears.
    static func showAgain() {
        UserDefaults.standard.set(generation + 1, forKey: generationKey)
        setReady(true)
    }
}

// MARK: - Tips

/// T1: Workout tab, on Most Rested's Start.
struct MostRestedTip: Tip {
    let generation: Int
    var id: String { "liteweight.tip.mostRested.\(generation)" }
    var title: Text { Text("Start with what's rested") }
    var message: Text? { Text("This card picks the saved workout whose muscles have rested longest.") }
    var image: Image? { Image(systemName: "lightbulb") }
    var rules: [Rule] { #Rule(LiteweightTipState.$isReady) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(3) }
}

/// T2: the logger's Log Set, until the first set is logged.
struct LogSetTip: Tip {
    let generation: Int
    var id: String { "liteweight.tip.logSet.\(generation)" }
    var title: Text { Text("Your next set is ready") }
    var message: Text? { Text("Weight and reps come from last time. Tap Log Set when you finish the set.") }
    var image: Image? { Image(systemName: "lightbulb") }
    var rules: [Rule] { #Rule(LiteweightTipState.$isReady) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(3) }
}

/// T3: under the rest strip, which only appears after a set is logged.
struct RestTimerTip: Tip {
    let generation: Int
    var id: String { "liteweight.tip.restTimer.\(generation)" }
    var title: Text { Text("Rest is running") }
    var message: Text? { Text("It counts down under the set you logged, and on your Lock Screen. Start the next set any time.") }
    var image: Image? { Image(systemName: "timer") }
    var rules: [Rule] { #Rule(LiteweightTipState.$isReady) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(3) }
}

/// T4: History, once there are two workouts to act on.
struct HistorySwipeTip: Tip {
    let generation: Int
    var id: String { "liteweight.tip.historySwipe.\(generation)" }
    var title: Text { Text("Swipe for quick actions") }
    var message: Text? { Text("Swipe right to repeat a workout, left to delete it. Touch and hold to preview.") }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Rule] { #Rule(LiteweightTipState.$isReady) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(3) }
}

/// T5: Home's pencil, after the first finished workout.
struct EditHomeTip: Tip {
    let generation: Int
    var id: String { "liteweight.tip.editHome.\(generation)" }
    var title: Text { Text("Make Home yours") }
    var message: Text? { Text("Tap the pencil to add, remove and reorder cards.") }
    var image: Image? { Image(systemName: "pencil") }
    var rules: [Rule] { #Rule(LiteweightTipState.$isReady) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(3) }
}

/// T6: an exercise chart's Pin to Home.
struct PinToHomeTip: Tip {
    let generation: Int
    var id: String { "liteweight.tip.pinToHome.\(generation)" }
    var title: Text { Text("Keep it on Home") }
    var message: Text? { Text("Pin this chart and it shows on Home after every workout.") }
    var image: Image? { Image(systemName: "pin") }
    var rules: [Rule] { #Rule(LiteweightTipState.$isReady) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(3) }
}

// MARK: - Presentation

// Tips sit in the layout, never in bubbles: on iOS 27 a popover tip measured its
// height before its text and clipped the message (owner's report, build 110).

/// A tip as its own List section. Show it only while `liteweightTracksTip` says
/// the tip is due, so a hidden tip leaves no empty row behind.
struct LiteweightTipSection<T: Tip>: View {
    let tip: T

    var body: some View {
        Section {
            TipView(tip)
                .tipBackground(LiteweightTheme.surface)
                .listRowInsets(EdgeInsets())
        }
    }
}

extension View {
    /// Mirrors whether `tip` should show into `isShowing`. Attach it to the List,
    /// not the section: a List never runs the task of a section that isn't there yet.
    func liteweightTracksTip<T: Tip>(_ tip: T, isShowing: Binding<Bool>) -> some View {
        modifier(LiteweightTipTracker(tip: tip, isShowing: isShowing))
    }
}

private struct LiteweightTipTracker<T: Tip>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tip: T
    @Binding var isShowing: Bool

    func body(content: Content) -> some View {
        content.task(id: tip.id) {
            for await shows in tip.shouldDisplayUpdates {
                withAnimation(LiteweightMotion.preferred(LiteweightMotion.fade, reduceMotion: reduceMotion)) {
                    isShowing = shows
                }
            }
        }
    }
}

/// A tip that sits in the layout, for places a bubble would cover what it explains.
/// It takes no space at all while hidden, so a stack around it needs no spacing of its own.
struct LiteweightInlineTip<T: Tip>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowing = false
    let tip: T
    var arrowEdge: Edge? = nil
    var topSpacing: CGFloat = 0
    var bottomSpacing: CGFloat = 0

    var body: some View {
        ZStack {
            if isShowing {
                TipView(tip, arrowEdge: arrowEdge)
                    .padding(.top, topSpacing)
                    .padding(.bottom, bottomSpacing)
                    .transition(.opacity)
            }
        }
        .task(id: tip.id) {
            for await shows in tip.shouldDisplayUpdates {
                withAnimation(LiteweightMotion.preferred(LiteweightMotion.fade, reduceMotion: reduceMotion)) {
                    isShowing = shows
                }
            }
        }
    }
}
