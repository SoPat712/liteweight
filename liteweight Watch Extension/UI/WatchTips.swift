//
//  WatchTips.swift
//  liteweight Watch Extension
//
//  The Watch's one first-use tip. watchOS has no tip bubbles and the Now page has
//  no spare room, so the tip opens as a short sheet over it, once.
//

import SwiftUI
import TipKit
import os.log

enum WatchTips {
    /// Simulator demos and screenshot flags never see tips.
    static var isSuppressed: Bool {
        let arguments = ProcessInfo.processInfo.arguments.dropFirst()
        #if DEBUG
        if arguments.contains("-liteweightShowTips") { return false }
        #endif
        return arguments.contains { $0.hasPrefix("--") || $0.hasPrefix("-liteweight") }
    }

    static func configure() {
        guard !isSuppressed else { return }
        do {
            try Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        } catch {
            os_log("Tips could not be configured: %@", type: .error, error.localizedDescription)
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-liteweightShowTips") { Tips.showAllTipsForTesting() }
        #endif
    }
}

/// T7: the first set on the Watch.
struct WatchCrownTip: Tip {
    var id: String { "liteweight.watch.tip.crown" }
    var title: Text { Text("Turn the Digital Crown") }
    var message: Text? { Text("It changes the box that's selected. Tap the other box to switch.") }
    var image: Image? { Image(systemName: "digitalcrown.arrow.clockwise") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

private struct WatchTipSheet<T: Tip>: ViewModifier {
    @State private var isPresented = false
    let tip: T

    func body(content: Content) -> some View {
        content
            .task(id: tip.id) {
                for await shows in tip.shouldDisplayUpdates { isPresented = shows }
            }
            .sheet(isPresented: $isPresented, onDismiss: { tip.invalidate(reason: .tipClosed) }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        tip.image?
                            .font(.title2)
                            .foregroundStyle(LiteweightTheme.accentText)
                            .accessibilityHidden(true)
                        tip.title
                            .font(.headline)
                            .foregroundStyle(LiteweightTheme.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        tip.message?
                            .font(.footnote)
                            .foregroundStyle(LiteweightTheme.secondaryText)
                        Button {
                            tip.invalidate(reason: .actionPerformed)
                            isPresented = false
                        } label: {
                            WatchActionLabel(title: "Got It")
                        }
                        .watchGlassButton(prominent: true)
                        .padding(.top, 4)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
    }
}

extension View {
    func watchTipSheet<T: Tip>(_ tip: T) -> some View {
        modifier(WatchTipSheet(tip: tip))
    }
}
