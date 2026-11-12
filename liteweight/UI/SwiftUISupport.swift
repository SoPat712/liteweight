//
//  SwiftUISupport.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 18.09.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import Charts
import UIKit
import MuscleMap
import WorkoutDataKit

// Palette and motion live in LiteweightStyle; metric fonts live in LiteweightMetricFont.

/// Search sits under the large title and moves into the bar's title row once the list scrolls (iOS 26+).
/// Earlier systems keep the pinned drawer.
struct TitleRowSearchModifier: ViewModifier {
    @Binding var text: String
    let prompt: String

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.searchable(text: $text, placement: .toolbarPrincipal, prompt: Text(prompt))
        } else {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
        }
    }
}

extension View {
    func titleRowSearchable(text: Binding<String>, prompt: String) -> some View {
        modifier(TitleRowSearchModifier(text: text, prompt: prompt))
    }
}

/// Flips the binding once a List has scrolled past its first row of the given height (iOS 18+; no-op before).
struct ListHeaderScrollTitleModifier: ViewModifier {
    let headerHeight: CGFloat
    @Binding var isNavigationTitleVisible: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > headerHeight
                } action: { _, visible in
                    isNavigationTitleVisible = visible
                }
        } else {
            content
        }
    }
}

/// Consistent compact durations and calendar-aware dates for workout lists.
enum LiteweightFormat {
    private struct FormatterKey: Hashable {
        let locale: Locale
        let calendar: Calendar
        let template: String
    }

    private static let formatterLock = NSLock()
    private static var dateFormatters: [FormatterKey: DateFormatter] = [:]
    private static var intervalFormatters: [FormatterKey: DateIntervalFormatter] = [:]

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0m" }
        guard seconds >= 60 else { return "<1m" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }

        // Formatting the whole hours also avoids overflowing Int for large finite intervals.
        let hours = String(format: "%.0f", (seconds / 3_600).rounded(.down))
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60)
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    static func listDate(
        _ date: Date?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        guard let date = date else { return "Unknown date" }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        let template = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? "EEE, MMM d" : "MMM d, yyyy"
        let key = FormatterKey(locale: locale, calendar: calendar, template: template)
        formatterLock.lock()
        defer { formatterLock.unlock() }
        let formatter: DateFormatter
        if let cached = dateFormatters[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            dateFormatters[key] = formatter
        }
        return formatter.string(from: date)
    }

    static func weekTitle(
        start: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        if let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) {
            if calendar.isDate(start, inSameDayAs: thisWeek.start) { return "This Week" }
            if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start),
               calendar.isDate(start, inSameDayAs: lastWeek) {
                return "Last Week"
            }
        }

        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let template = calendar.component(.year, from: end) == calendar.component(.year, from: now)
            ? "MMMd" : "yMMMd"
        let key = FormatterKey(locale: locale, calendar: calendar, template: template)
        formatterLock.lock()
        defer { formatterLock.unlock() }
        let formatter: DateIntervalFormatter
        if let cached = intervalFormatters[key] {
            formatter = cached
        } else {
            formatter = DateIntervalFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateTemplate = template
            intervalFormatters[key] = formatter
        }
        return formatter.string(from: start, to: end)
    }
}

/// The same number/unit hierarchy for summary columns, data rows and chart headlines.
/// A single Text keeps the unit baseline aligned and lets it wrap at accessibility sizes.
struct LiteweightMetricValue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: String
    var unit: String? = nil
    var style: Font.TextStyle = .title2
    var weight: Font.Weight = .bold
    var unitStyle: Font.TextStyle = .footnote
    var tint: Color = LiteweightTheme.primaryText
    /// A running clock passes false: a roll every second kept the logger redrawing about
    /// 40% of the time while idle (build 130).
    var animatesChanges = true

    var body: some View {
        let text = Text(value).font(.liteweightMetric(style, weight: weight)).foregroundColor(tint)
            + Text(unit.map { " " + $0 } ?? "")
                .font(.system(unitStyle).weight(.semibold)).foregroundColor(LiteweightTheme.secondaryText)
        if animatesChanges {
            // Every in-place number change rolls its digits; Reduce Motion fades.
            text
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: value)
                .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: unit)
        } else {
            text.contentTransition(.identity)
        }
    }
}

extension String {
    /// Display form of a catalog equipment key: "ez-curl-bar" → "EZ Curl Bar".
    var equipmentTitle: String {
        let words = replacingOccurrences(of: "-", with: " ").capitalized
        let fixes = ["Ez ": "EZ ", "T Bar": "T-Bar", "Skierg": "SkiErg", "Bosu": "BOSU"]
        return fixes.reduce(words) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }
}

/// Shared inline summary for the same workout wherever it appears in a list.
struct LiteweightWorkoutMetricLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let duration: String
    let sets: Int
    let volume: String
    let unit: String

    var body: some View {
        line
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: "\(duration)|\(sets)|\(volume)|\(unit)")
    }

    private var line: some View {
        (Text(duration).foregroundColor(LiteweightTheme.primaryText)
         + Text(" · ").foregroundColor(LiteweightTheme.secondaryText)
         + Text("\(sets)").foregroundColor(LiteweightTheme.primaryText)
         + Text(sets == 1 ? " set" : " sets").font(.caption.weight(.semibold)).foregroundColor(LiteweightTheme.secondaryText)
         + Text(" · ").foregroundColor(LiteweightTheme.secondaryText)
         + Text(volume).foregroundColor(LiteweightTheme.primaryText)
         + Text(" \(unit)").font(.caption.weight(.semibold)).foregroundColor(LiteweightTheme.secondaryText))
            .font(.liteweightMetric(.subheadline, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LiteweightLiquidGlassPillModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(tint).interactive(),
                in: Capsule(style: .continuous)
            )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(LiteweightTheme.outline.opacity(0.52), lineWidth: 1)
                )
        }
    }
}

extension View {
    /// Shared transparent pill chrome for UI that floats above changing content.
    func liteweightLiquidGlassPill(
        tint: Color = LiteweightTheme.accent.opacity(0.08)
    ) -> some View {
        modifier(LiteweightLiquidGlassPillModifier(tint: tint))
    }

    /// Glass chrome for hero and summary clusters that sit above scrolling
    /// content. Unlike `LiteweightCard` this is a refracting layer, not an opaque
    /// surface, so it reads as depth instead of another stacked panel.
    func liteweightLiquidGlassSurface(
        cornerRadius: CGFloat = LiteweightTheme.heroCornerRadius,
        tint: Color = LiteweightTheme.accent.opacity(0.06)
    ) -> some View {
        modifier(LiteweightLiquidGlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Secondary action chrome. Every button that floats over scrolling content
    /// should use this so a screen never mixes glass and flat bordered fills.
    @ViewBuilder
    func liteweightGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// The single primary action on a surface.
    @ViewBuilder
    func liteweightProminentGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

private struct LiteweightLiquidGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(LiteweightTheme.outline.opacity(0.32), lineWidth: 1))
        }
    }
}

private struct LiteweightSetCompletionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isComplete: Bool
    let feedbackEnabled: Bool
    let tint: Color
    let settledOpacity: Double
    let peakOpacity: Double
    let sweeps: Bool
    @State private var lastCompletion: Bool
    @State private var fillProgress: CGFloat
    @State private var fillOpacity: Double

    init(isComplete: Bool, feedbackEnabled: Bool, tint: Color, settledOpacity: Double, peakOpacity: Double, sweeps: Bool) {
        self.isComplete = isComplete
        self.feedbackEnabled = feedbackEnabled
        self.tint = tint
        self.settledOpacity = settledOpacity
        self.peakOpacity = peakOpacity
        self.sweeps = sweeps
        _lastCompletion = State(initialValue: isComplete)
        _fillProgress = State(initialValue: isComplete ? 1 : 0)
        _fillOpacity = State(initialValue: isComplete ? settledOpacity : 0)
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: LiteweightTheme.compactCornerRadius, style: .continuous)
                    .fill(tint.opacity(fillOpacity))
                    .scaleEffect(x: reduceMotion ? 1 : fillProgress, anchor: .leading)
                    .clipShape(RoundedRectangle(
                        cornerRadius: LiteweightTheme.compactCornerRadius, style: .continuous
                    ))
                    .allowsHitTesting(false)
            }
            .task(id: isComplete) {
                // Existing completed rows appear settled, without replaying feedback.
                guard lastCompletion != isComplete else {
                    fillProgress = isComplete ? 1 : 0
                    fillOpacity = isComplete ? settledOpacity : 0
                    return
                }
                lastCompletion = isComplete
                if isComplete, !sweeps {
                    fillProgress = 1
                    withAnimation(LiteweightMotion.preferred(LiteweightMotion.reveal, reduceMotion: reduceMotion)) {
                        fillOpacity = settledOpacity
                    }
                    return
                }
                withAnimation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion)) {
                    fillProgress = isComplete ? 1 : 0
                    fillOpacity = isComplete ? (reduceMotion ? settledOpacity : peakOpacity) : 0
                }
                guard isComplete, !reduceMotion else { return }
                do {
                    try await Task.sleep(for: LiteweightMotion.duration(milliseconds: 420))
                } catch {
                    return
                }
                withAnimation(LiteweightMotion.preferred(LiteweightMotion.fade, reduceMotion: reduceMotion)) {
                    fillOpacity = settledOpacity
                }
            }
            .onChange(of: settledOpacity) { _, opacity in
                if isComplete { fillOpacity = opacity }
            }
            .sensoryFeedback(.success, trigger: isComplete) { _, completed in
                completed && feedbackEnabled
            }
    }
}

private struct LiteweightStaggeredEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(LiteweightMotion.preferred(
                    LiteweightMotion.snappy.delay(Double(max(index, 0)) * 0.04),
                    reduceMotion: reduceMotion
                )) {
                    hasAppeared = true
                }
            }
            // Plays once. Resetting on disappear hides List rows that were
            // prefetched off screen and replays the entrance on every scroll.
    }
}

extension View {
    /// Leading accent sweep, faint settled fill, and completion success haptic.
    /// Apply to the row content inside its existing inset; this adds no geometry.
    /// Callers still own check symbols, field states, and the completion label.
    /// Reduce Motion uses a fade and keeps the haptic. With `sweeps: false` the
    /// fill fades straight to its settled opacity instead.
    func liteweightSetCompletion(
        isComplete: Bool,
        feedbackEnabled: Bool = true,
        tint: Color = LiteweightTheme.accent,
        settledOpacity: Double = 0.12,
        peakOpacity: Double = 0.24,
        sweeps: Bool = true
    ) -> some View {
        modifier(LiteweightSetCompletionModifier(
            isComplete: isComplete, feedbackEnabled: feedbackEnabled,
            tint: tint, settledOpacity: settledOpacity, peakOpacity: peakOpacity, sweeps: sweeps
        ))
    }

    /// Fades and rises 8 points on appearance, delayed 40 ms per zero-based index.
    /// Reduce Motion uses an immediate short fade without translation or stagger.
    func liteweightStaggeredEntrance(index: Int) -> some View {
        modifier(LiteweightStaggeredEntranceModifier(index: index))
    }
}

/// Rest countdown ring: pass the fraction remaining (1 = full, 0 = elapsed).
/// Timer state and ticking stay with the caller. Hide from accessibility when
/// the containing pill already announces the remaining time.
struct LiteweightRestRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    var size: CGFloat = 34
    var tint: Color = LiteweightTheme.metricTime
    var accessibilityLabel: String = "Rest remaining"

    private var fraction: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    var body: some View {
        ZStack {
            Circle().stroke(LiteweightTheme.tertiaryFill, lineWidth: 4)
            if reduceMotion {
                progressArc.id(fraction).transition(.opacity)
            } else {
                progressArc
            }
        }
        .padding(2)
        .frame(width: size, height: size)
        .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }

    private var progressArc: some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .opacity(fraction > 0 ? 1 : 0)
    }
}

struct LiteweightConfirmationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = LiteweightTheme.danger

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(LiteweightTheme.onAccent.opacity(isEnabled ? 1 : 0.62))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: LiteweightTheme.cornerRadius, style: .continuous)
                    .fill(
                        isEnabled
                            ? tint.opacity(configuration.isPressed ? 0.76 : 1)
                            : tint.opacity(0.34)
                    )
            )
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
    }
}

/// Compact Cupertino chrome for workout utilities presented from the bottom.
extension View {
    /// Tapping a number field selects its value, so typing replaces it without a double tap.
    func liteweightSelectsNumberOnFocus() -> some View {
        onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
            guard let field = notification.object as? UITextField,
                  field.keyboardType == .decimalPad || field.keyboardType == .numberPad else { return }
            // The tap places its caret after editing begins.
            DispatchQueue.main.async {
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            }
        }
    }
}

struct LiteweightUtilitySheet<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let showsDone: Bool
    let onClose: () -> Void
    private let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        showsDone: Bool = true,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.showsDone = showsDone
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LiteweightTheme.horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }

                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onClose)
                    }
                }
            }
        }
        .liteweightScreen()
    }
}

/// A bottom confirmation surface for consequential actions. Destructive roles
/// use the platform red and the secondary action remains visually quiet.
struct LiteweightConfirmationSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var tint: Color = LiteweightTheme.danger
    var cancelTitle: String = "Cancel"
    var secondaryTitle: String = "Keep current data"
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 8)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)

                Spacer(minLength: 0)

                Button(confirmTitle, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(tint)
                    .frame(maxWidth: .infinity)

                Button(secondaryTitle, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, LiteweightTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle, action: onCancel)
                }
            }
        }
        .liteweightScreen()
    }
}

/// A compact bottom-modal result for completed operations and recoverable
/// failures using the same platform hierarchy as other sheets.
struct LiteweightStatusSheet: View {
    @Environment(\.dismiss) private var dismiss

    let headerTitle: String
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let actionTitle: String

    init(
        headerTitle: String = "Status",
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        actionTitle: String = "Done"
    ) {
        self.headerTitle = headerTitle
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.actionTitle = actionTitle
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Image(systemName: systemImage)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.top, 8)

                        Text(title)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 340)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LiteweightTheme.horizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                }

                Button(actionTitle) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LiteweightTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
            }
            .navigationTitle(headerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .liteweightScreen()
        .presentationDetents([.height(390), .medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// A consistent Cupertino date row used anywhere a workout or body entry
/// exposes an editable timestamp.
struct LiteweightDateTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let range: ClosedRange<Date>
    let onApply: (Date) -> Void

    @State private var selection: Date

    init(
        title: String,
        subtitle: String,
        initialDate: Date,
        range: ClosedRange<Date>,
        onApply: @escaping (Date) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.range = range
        self.onApply = onApply
        _selection = State(initialValue: min(max(initialDate, range.lowerBound), range.upperBound))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text(selection.formatted(date: .complete, time: .omitted))
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(selection.formatted(date: .omitted, time: .shortened))
                            .font(.liteweightMetric(.title2, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    DatePicker(
                        title,
                        selection: $selection,
                        in: range,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(height: 190)
                    .clipped()
                }
                .padding(.horizontal, LiteweightTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onApply(selection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .liteweightScreen()
        .presentationDetents([.height(450), .large])
        .presentationDragIndicator(.visible)
    }
}

/// Four slanted tiers, with one dot for each whole-number session rating.
struct EffortRatingGraph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Binding var rating: Int
    var allowsUnrated: Bool = false
    @ScaledMetric(relativeTo: .caption) private var levelLabelHeight: CGFloat = 18
    @State private var selectionFeedback = 0
    private static let levelGap: CGFloat = 4
    private static let tierGap: CGFloat = 12

    private var userRating: Binding<Int> {
        Binding(get: { rating }, set: {
            guard rating != $0 else { return }
            rating = $0
            selectionFeedback += 1
        })
    }

    private var tier: EffortTierPalette { .tier(for: rating) }
    private var readoutColor: Color {
        rating == 0 ? LiteweightTheme.secondaryText : tier.textColor(in: colorScheme)
    }

    var body: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { readout }
                VStack(spacing: 4) { readout }
            }
            .foregroundStyle(readoutColor)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                GeometryReader { proxy in
                    let layout = EffortLevelLayout(width: proxy.size.width, levelGap: Self.levelGap, tierGap: Self.tierGap)
                    ZStack(alignment: .leading) {
                        EffortLevelBars(rating: rating, levelGap: Self.levelGap, tierGap: Self.tierGap,
                                        cornerRadius: 7, inactiveColor: LiteweightTheme.solidTrack)
                        // Each level owns its full column, so a tap anywhere above a number picks it.
                        HStack(spacing: 0) {
                            ForEach(EffortLevelLayout.levels, id: \.self) { level in
                                Button { userRating.wrappedValue = level } label: {
                                    Color.clear.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(width: layout.barWidth + layout.gap(after: level))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .liteweightHorizontalScrub(includingTaps: false) { location in
                        userRating.wrappedValue = layout.level(at: location.x)
                    } onEnded: { }
                }
                .frame(height: 170)

                GeometryReader { proxy in
                    let layout = EffortLevelLayout(width: proxy.size.width, levelGap: Self.levelGap, tierGap: Self.tierGap)
                    ForEach(EffortLevelLayout.levels, id: \.self) { level in
                        Text("\(level)")
                            .font(.liteweightMetric(.caption, weight: .semibold))
                            .foregroundStyle(level == rating ? LiteweightTheme.primaryText : LiteweightTheme.secondaryText)
                            .position(x: layout.minX(of: level) + layout.barWidth / 2, y: proxy.size.height / 2)
                    }
                }
                .frame(height: levelLabelHeight)
            }
        }
        .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: rating)
        .sensoryFeedback(.selection, trigger: selectionFeedback) { _, _ in SettingsStore.shared.workoutHaptics }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session effort")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 10, \(tier.title)")
        .accessibilityHint("Swipe up or down to adjust")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: userRating.wrappedValue = min(rating + 1, 10)
            case .decrement: userRating.wrappedValue = max(rating - 1, allowsUnrated ? 0 : 1)
            default: break
            }
        }
    }

    @ViewBuilder private var readout: some View {
        Text(rating == 0 ? "—" : "\(rating)")
            .font(.liteweightMetric(.largeTitle))
            .contentTransition(reduceMotion ? .opacity : .numericText())
        Text(rating == 0 ? "Not rated" : tier.title)
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            // Changes at once, so two tier names never overlap mid-animation.
            .transaction { $0.animation = nil }
    }
}

/// Each half step is a separate segment of one continuous slanted ramp.
struct RPEGraph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 18
    @Binding var selection: Double?
    @State private var selectionFeedback = 0
    @State private var lastFeedback = Date.distantPast

    private func select(_ value: Double) {
        guard selection != value else { return }
        selection = value
        // A fast scrub ran per-step ticks together into a buzz; keep them crisp.
        let now = Date()
        guard now.timeIntervalSince(lastFeedback) >= 0.06 else { return }
        lastFeedback = now
        selectionFeedback += 1
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(0, (proxy.size.width - 40) / 11)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<11) { index in
                        bar(index: index, width: width, totalWidth: proxy.size.width)
                    }
                }
                .contentShape(Rectangle())
                .liteweightHorizontalScrub(includingTaps: false) { location in
                    guard width > 0 else { return }
                    let index = min(max(Int(floor((location.x + 2) / (width + 4))), 0), 10)
                    select(5 + Double(index) * 0.5)
                } onEnded: { }
            }
            .frame(height: 96)

            GeometryReader { proxy in
                let width = max(0, (proxy.size.width - 40) / 11)
                ForEach(0..<6) { index in
                    Text("\(5 + index)")
                        .font(.liteweightMetric(.caption, weight: .semibold))
                        .foregroundStyle(LiteweightTheme.secondaryText)
                        .position(x: CGFloat(index * 2) * (width + 4) + width / 2, y: labelHeight / 2)
                }
            }
            .frame(height: labelHeight)
            .accessibilityHidden(true)
        }
        // An ease: scrubbing retargets every step, and restarting springs wobbled.
        .animation(LiteweightMotion.fade, value: selection)
        .sensoryFeedback(.selection, trigger: selectionFeedback) { _, _ in SettingsStore.shared.workoutHaptics }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set RPE")
        .accessibilityValue(selection.map { "RPE \(String(format: "%g", $0)), \(RPE.title($0) ?? "")" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(min((selection ?? 4.5) + 0.5, 10))
            case .decrement: select(max((selection ?? 5.5) - 0.5, 5))
            default: break
            }
        }
    }

    private func bar(index: Int, width: CGFloat, totalWidth: CGFloat) -> some View {
        let x0 = CGFloat(index) * (width + 4)
        let x1 = x0 + width
        let value = 5 + Double(index) * 0.5
        let divisor = max(totalWidth, 1)
        let shape = SlantedBarShape(leftHeight: 0.28 + 0.72 * x0 / divisor,
                                    rightHeight: 0.28 + 0.72 * x1 / divisor,
                                    cornerRadius: min(8, width / 2.6))
        // A tap selects a bar directly; dragging across the ramp scrubs.
        return Button { select(value) } label: {
            shape
                .fill(selection.map { value <= $0 } == true ? LiteweightTheme.metricEffort : Color(uiColor: .systemFill))
                .frame(width: width)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal controls yield vertical intent to their containing scroll view.
@available(iOS 18.0, *)
private struct LiteweightHorizontalScrubRecognizer: UIGestureRecognizerRepresentable {
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: onChanged(context.converter.localLocation)
        case .ended:
            onChanged(context.converter.localLocation)
            onEnded()
        case .cancelled, .failed: onEnded()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

extension View {
    @ViewBuilder
    func liteweightHorizontalScrub(
        includingTaps: Bool = true,
        onChanged: @escaping (CGPoint) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        let tap = SpatialTapGesture().onEnded { value in
            onChanged(value.location)
            onEnded()
        }
        if #available(iOS 18.0, *) {
            let horizontal = self.gesture(LiteweightHorizontalScrubRecognizer(onChanged: onChanged, onEnded: onEnded))
            if includingTaps { horizontal.simultaneousGesture(tap) } else { horizontal }
        } else {
            let horizontal = self.simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        onChanged(value.location)
                    }
                    .onEnded { _ in onEnded() }
            )
            if includingTaps { horizontal.simultaneousGesture(tap) } else { horizontal }
        }
    }
}

/// A reusable Cupertino bottom modal for timed exercise targets and logged
/// efforts. Duration is adjusted with the same direct radial interaction as
/// liteweight's rest timer, so time-based sets never fall back to a keyboard-only
/// text field or a platform picker.
struct LiteweightDurationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let systemImage: String
    let secondaryActionTitle: String?
    let onSecondaryAction: (() -> Void)?
    let shouldDismiss: () -> Bool
    let onApply: (TimeInterval) -> Void

    @State private var selection: TimeInterval
    @State private var wheelSteps = 0

    private let minimumDuration: TimeInterval
    private let maximumDuration: TimeInterval
    private let durationStep: TimeInterval
    private let presets: [TimeInterval]

    init(
        title: String = "Set duration",
        subtitle: String = "Choose the target time for this set",
        systemImage: String = "stopwatch.fill",
        initialDuration: TimeInterval,
        minimumDuration: TimeInterval = 5,
        maximumDuration: TimeInterval = 3_600,
        durationStep: TimeInterval = 5,
        presets: [TimeInterval] = [30, 45, 60, 90, 120, 180, 300, 600],
        secondaryActionTitle: String? = nil,
        onSecondaryAction: (() -> Void)? = nil,
        shouldDismiss: @escaping () -> Bool = { true },
        onApply: @escaping (TimeInterval) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.minimumDuration = minimumDuration
        self.maximumDuration = max(maximumDuration, minimumDuration)
        self.durationStep = max(durationStep, 1)
        self.presets = presets.filter { $0 >= minimumDuration && $0 <= maximumDuration }
        self.secondaryActionTitle = secondaryActionTitle
        self.onSecondaryAction = onSecondaryAction
        self.shouldDismiss = shouldDismiss
        self.onApply = onApply
        _selection = State(
            initialValue: min(max(initialDuration, minimumDuration), max(maximumDuration, minimumDuration))
        )
    }

    var body: some View {
        LiteweightUtilitySheet(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            onClose: { dismiss() }
        ) {
            VStack(spacing: 14) {
                LiteweightDurationWheel(
                    selection: Binding(get: { selection }, set: {
                        guard selection != $0 else { return }
                        selection = $0
                        wheelSteps += 1
                    }),
                    minimumDuration: minimumDuration,
                    maximumDuration: maximumDuration,
                    secondsStep: durationStep
                )

                if !presets.isEmpty {
                    LiteweightSegmentedPicker(title: "Presets", selection: $selection, segments: presets.map {
                        .init(value: $0, title: durationTitle($0))
                    })
                    .padding(.horizontal, LiteweightTheme.horizontalPadding)
                }

                VStack(spacing: 10) {
                    Button {
                        onApply(selection)
                        if shouldDismiss() { dismiss() }
                    } label: {
                        Text("Use \(durationTitle(selection))")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if let secondaryActionTitle, let onSecondaryAction {
                        Button {
                            onSecondaryAction()
                            if shouldDismiss() { dismiss() }
                        } label: {
                            Text(secondaryActionTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(.horizontal, LiteweightTheme.horizontalPadding)
            }
            .padding(.bottom, 18)
        }
        .presentationDetents(presentationDetents)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: wheelSteps) { _, _ in SettingsStore.shared.workoutHaptics }
    }

    private var presentationDetents: Set<PresentationDetent> {
        secondaryActionTitle == nil ? [.height(470), .large] : [.height(540), .large]
    }

    private func durationTitle(_ duration: TimeInterval) -> String {
        LiteweightDurationFormat.title(duration)
    }
}

/// Minute and second wheels, the same control watchOS uses for weight and reps.
/// Replaces liteweight's former custom radial dial: a drag-around-a-circle gesture has
/// no platform equivalent, no Digital Crown analogue, and poor VoiceOver support.
struct LiteweightDurationWheel: View {
    @Binding var selection: TimeInterval

    let minimumDuration: TimeInterval
    let maximumDuration: TimeInterval
    let secondsStep: TimeInterval

    private var maximumMinutes: Int {
        max(Int(maximumDuration) / 60, 0)
    }

    private var secondsValues: [Int] {
        let step = max(Int(secondsStep), 1)
        guard step < 60 else { return [0] }
        return Array(stride(from: 0, to: 60, by: step))
    }

    private var minuteSelection: Binding<Int> {
        Binding(
            get: { min(Int(selection) / 60, maximumMinutes) },
            set: { selection = clamped(TimeInterval($0 * 60 + Int(selection) % 60)) }
        )
    }

    private var secondSelection: Binding<Int> {
        Binding(
            get: {
                let current = Int(selection) % 60
                return secondsValues.min(by: { abs($0 - current) < abs($1 - current) }) ?? 0
            },
            set: { selection = clamped(TimeInterval((Int(selection) / 60) * 60 + $0)) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            wheel(
                label: "Minutes",
                unit: "min",
                values: Array(0...maximumMinutes),
                selection: minuteSelection
            )

            wheel(
                label: "Seconds",
                unit: "sec",
                values: secondsValues,
                selection: secondSelection
            )
        }
        .frame(height: 150)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Duration")
        .accessibilityValue(LiteweightDurationFormat.title(selection))
    }

    private func wheel(
        label: String,
        unit: String,
        values: [Int],
        selection: Binding<Int>
    ) -> some View {
        HStack(spacing: 4) {
            Picker(label, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text("\(value)")
                        .monospacedDigit()
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()

            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func clamped(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, minimumDuration), max(maximumDuration, minimumDuration))
    }
}

/// One duration string for the logger, rest timer, and Live Activity so a
/// 90-second rest never renders as "1:30" in one place and "90s" in another.
enum LiteweightDurationFormat {
    static func title(_ duration: TimeInterval) -> String {
        let seconds = Int(max(duration, 0).rounded())
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private struct LiteweightTabTitle: ViewModifier {
    let title: String
    var showsBrandMark = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolled = false

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                // Kept for the back button and app switcher; the bar shows the leading text instead.
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(title)
                                .font(.largeTitle.bold())
                                .foregroundStyle(LiteweightTheme.primaryText)
                            // TEMPORARY: the plate mark stands in until the owner's new logo (build 121).
                            if showsBrandMark { LiteweightPlateMark() }
                        }
                            .fixedSize()
                            .opacity(scrolled ? 0 : 1)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityHidden(scrolled)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 12
                } action: { _, isScrolled in
                    withAnimation(LiteweightMotion.preferred(LiteweightMotion.fade, reduceMotion: reduceMotion)) {
                        scrolled = isScrolled
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inlineLarge)
        }
    }
}

// MARK: - Native pull-down actions

extension View {
    func liteweightScreen() -> some View {
        self
            .accentColor(LiteweightTheme.accent)
    }

    /// A tab root's title: large beside the toolbar buttons, then gone once the list
    /// scrolls, so only the floating buttons stay over a translucent edge.
    func liteweightTabTitle(_ title: String, showsBrandMark: Bool = false) -> some View {
        modifier(LiteweightTabTitle(title: title, showsBrandMark: showsBrandMark))
    }

    @ViewBuilder
    func defaultScrollAnchorCompat_trailing() -> some View {
        if #available(iOS 18.0, *) {
            defaultScrollAnchor(.trailing)
        } else {
            self
        }
    }
}

struct TextCaseNil: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 14.0, *) {
            content.textCase(nil)
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func textCaseCompat_nil() -> some View {
        if #available(iOS 14.0, *) {
            textCase(nil)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder
    func listStyleCompat_InsetGroupedListStyle() -> some View {
        if #available(iOS 14.0, *) {
            listStyle(InsetGroupedListStyle())
        } else {
            listStyle(GroupedListStyle())
        }
    }
}

extension View {
    @ViewBuilder
    func redacted_compat() -> some View {
        if #available(iOS 14.0, *) {
            redacted(reason: .placeholder)
        }
    }
}

extension View {
    /// Applies a modifier to a view conditionally.
    ///
    /// - Parameters:
    ///   - condition: The condition to determine if the content should be applied.
    ///   - content: The modifier to apply to the view.
    /// - Returns: The modified view.
    @ViewBuilder func modifier<T: View>(
        if condition: @autoclosure () -> Bool,
        then content: (Self) -> T
    ) -> some View {
        if condition() {
            content(self)
        } else {
            self
        }
    }
    
    /// Applies a modifier to a view conditionally.
    ///
    /// - Parameters:
    ///   - condition: The condition to determine the content to be applied.
    ///   - trueContent: The modifier to apply to the view if the condition passes.
    ///   - falseContent: The modifier to apply to the view if the condition fails.
    /// - Returns: The modified view.
    @ViewBuilder func modifier<TrueContent: View, FalseContent: View>(
        if condition: @autoclosure () -> Bool,
        then trueContent: (Self) -> TrueContent,
        else falseContent: (Self) -> FalseContent
    ) -> some View {
        if condition() {
            trueContent(self)
        } else {
            falseContent(self)
        }
    }
}

/// Normalizes catalog muscle names for the detail and live-workout maps.
func liteweightMapMuscle(_ rawName: String) -> Muscle? {
    switch rawName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case "abs", "abdominals", "core": return .abs
    case "lower abs", "lowerabs": return .lowerAbs
    case "obliques": return .obliques
    case "serratus", "serratus anterior": return .serratus
    case "biceps", "biceps brachii", "brachialis": return .biceps
    case "triceps", "triceps brachii": return .triceps
    case "forearm", "forearms", "forerm", "wrists", "wrist flexors", "wrist extensors", "grip muscles": return .forearm
    case "hands": return .hands
    case "shoulders", "deltoid", "deltoids", "delts": return .deltoids
    case "rear deltoid", "rear deltoids", "reardeltoid": return .rearDeltoid
    case "rotator cuff", "rotatorcuff": return .rotatorCuff
    case "trapezius", "traps", "levator scapulae": return .trapezius
    case "rhomboids": return .rhomboids
    case "neck", "sternocleidomastoid": return .neck
    case "chest", "pectorals", "pectoralis major": return .chest
    case "upper chest", "upperchest": return .upperChest
    case "lats", "latissimus", "latissimus dorsi", "upper back", "upperback", "back": return .upperBack
    case "lower back", "lowerback", "spine", "erector spinae": return .lowerBack
    case "glutes", "glutaeus maximus", "abductors": return .gluteal
    case "hamstrings", "ischiocrural muscles": return .hamstring
    case "quadriceps", "quads": return .quadriceps
    case "adductors", "groin", "inner thighs": return .adductors
    case "hip flexor", "hip flexors", "hipflexors": return .hipFlexors
    case "calves", "gastrocnemius", "soleus": return .calves
    case "shin", "shins", "tibialis", "tibialis anterior": return .tibialis
    case "ankles", "ankle stabilizers": return .ankles
    case "feet": return .feet
    default: return nil
    }
}


extension View {
    /// Scrub horizontally, leaving vertical pans to the enclosing List.
    func liteweightHorizontalChartScrubbing(onEnded: @escaping () -> Void) -> some View {
        chartGesture { _ in SpatialTapGesture() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        LiteweightChartScrubber(
                            onChanged: { x in proxy.selectXValue(at: min(max(x, 0), frame.width)) },
                            onEnded: onEnded
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityHidden(true)
                    }
                }
            }
    }
}

private struct LiteweightChartScrubber: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panChanged(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: LiteweightChartScrubber
        init(parent: LiteweightChartScrubber) { self.parent = parent }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func panChanged(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began, .changed: parent.onChanged(pan.location(in: pan.view).x)
            case .ended, .cancelled, .failed: parent.onEnded()
            default: break
            }
        }
    }
}

// MARK: - Muscle colors

/// One data-driven line in the app's voice under a tab's title (build 121): secondary text
/// with its key facts in bold primary (compose with `Text` concatenation). It sits as the
/// tab's first, unboxed list row so it scrolls away with the title.
struct LiteweightVoiceLine: View {
    let text: Text

    var body: some View {
        text
            .font(.subheadline)
            .foregroundStyle(LiteweightTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A bold, primary-colored fact inside a voice line.
    static func fact(_ value: String) -> Text {
        Text(value).bold().foregroundColor(LiteweightTheme.primaryText)
    }
}

/// A tab's voice line as an empty section's header (build 122). Rows keep a 44 pt minimum and
/// sections add their full spacing, which left the line floating between the title and the first
/// card; a header hugs its text and the custom spacing keeps the first card close.
struct LiteweightVoiceSection: View {
    let text: Text

    var body: some View {
        Section {
        } header: {
            LiteweightVoiceLine(text: text)
                .textCase(nil)
        }
        .listSectionSpacing(10)
    }
}

/// TEMPORARY brand mark: today's app icon's three plates (red, blue, yellow) as three small
/// rounded bars. The owner is replacing the logo; swap this view and the `plate*` colors in
/// `LiteweightTheme` when the new mark lands (build 121). Decorative, so hidden from VoiceOver.
struct LiteweightPlateMark: View {
    @ScaledMetric(relativeTo: .title) private var height: CGFloat = 26
    var scale: CGFloat = 1

    var body: some View {
        let barHeight = height * scale
        HStack(spacing: barHeight * 0.16) {
            ForEach([LiteweightTheme.plateRed, LiteweightTheme.plateBlue, LiteweightTheme.plateYellow], id: \.self) { color in
                RoundedRectangle(cornerRadius: barHeight * 0.14, style: .continuous)
                    .fill(color)
                    .frame(width: barHeight * 0.28, height: barHeight)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Gold capsule for a personal record: a small spark and "PR" (build 121). Gold always means
/// an achievement; the badge says so in words too, so it is never color alone.
struct LiteweightPRBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
                .font(.caption2.weight(.bold))
            Text("PR")
                .font(.caption.weight(.heavy))
        }
        .foregroundStyle(LiteweightTheme.onAchievement)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(LiteweightTheme.achievement, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Personal record")
    }
}

/// A muscle group's chip: its color as a soft fill, the name in primary text, and an
/// optional rest detail ("today", "3d") led by a status dot (amber still recovering,
/// green rested). The same chip on Most Rested, saved workouts and History.
struct LiteweightMuscleChip: View {
    let group: String
    var detail: String?
    var status: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let status {
                Circle().fill(status).frame(width: 7, height: 7)
            }
            (Text(HomeWeekSummary.displayName(group))
             + (detail.map { Text(" " + $0).font(.liteweightMetric(.footnote, weight: .semibold)) } ?? Text("")))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LiteweightTheme.primaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(LiteweightTheme.muscleContainer(group), in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The leading tile on a workout row, in the color of the muscle group it trained most.
struct LiteweightMuscleTile: View {
    let group: String?
    var size: CGFloat = 34

    /// Core and Chest share a letter, so Core keeps two.
    private var initial: String {
        guard let group else { return "" }
        return String(HomeWeekSummary.displayName(group).prefix(group == "abdominals" ? 2 : 1))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LiteweightTheme.muscle(group).gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * (initial.count > 1 ? 0.38 : 0.46), weight: .bold))
                    .foregroundStyle(LiteweightTheme.onAccent)
            }
            .accessibilityHidden(true)
    }
}

/// Wraps chips onto as many lines as they need.
struct LiteweightChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !row.indices.isEmpty, row.width + spacing + itemWidth > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Segmented picker

/// The app's segmented control (§9.4): the system segmented picker, so it keeps native dragging,
/// glass and VoiceOver, with the selected segment in the accent color (`applyAppearance()`).
/// Only selection taps give haptic feedback; a value matching no segment selects none.
struct LiteweightSegmentedPicker<Value: Hashable>: View {
    struct Segment {
        let value: Value
        let title: String
        var accessibilityLabel: String?
    }

    @State private var taps = 0
    let title: String
    @Binding var selection: Value
    let segments: [Segment]

    var body: some View {
        Picker(title, selection: Binding(get: { selection }, set: { value in
            guard value != selection else { return }
            selection = value
            taps += 1
        })) {
            ForEach(segments.indices, id: \.self) { index in
                Text(segments[index].title).tag(segments[index].value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .sensoryFeedback(.selection, trigger: taps) { _, _ in SettingsStore.shared.workoutHaptics }
        // Short titles like "kg" read as full words.
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(segments.indices, id: \.self) { index in
                    Text(segments[index].accessibilityLabel ?? segments[index].title).tag(segments[index].value)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// SwiftUI can't color a segmented picker's thumb, so every segmented control in the app gets the
/// accent thumb and on-accent selected text once at launch.
enum LiteweightSegmentedAppearance {
    @MainActor static func apply() {
        let control = UISegmentedControl.appearance()
        control.selectedSegmentTintColor = LiteweightPalette.uiColor(\.accent)
        control.setTitleTextAttributes([.foregroundColor: LiteweightPalette.uiColor(\.onAccent)], for: .selected)
    }
}

// MARK: - Stepper

/// The logger's round −/+ controls, with repeat, bounds and a native stepper for VoiceOver (§9.4.1).
struct LiteweightStepper<Label: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var taps = 0
    private let onIncrement: (() -> Void)?
    private let onDecrement: (() -> Void)?
    private let hidesLabel: Bool
    private let label: Label

    init(onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, hidesLabel: Bool = false,
         @ViewBuilder label: () -> Label) {
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
        self.hidesLabel = hidesLabel
        self.label = label()
    }

    init<V: Strideable>(value: Binding<V>, in range: ClosedRange<V>, step: V.Stride = 1,
                       hidesLabel: Bool = false, @ViewBuilder label: () -> Label) {
        self.init(
            onIncrement: value.wrappedValue >= range.upperBound ? nil : {
                value.wrappedValue = min(max(value.wrappedValue.advanced(by: step), range.lowerBound), range.upperBound)
            },
            onDecrement: value.wrappedValue <= range.lowerBound ? nil : {
                value.wrappedValue = min(max(value.wrappedValue.advanced(by: -step), range.lowerBound), range.upperBound)
            },
            hidesLabel: hidesLabel, label: label
        )
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if !hidesLabel {
                label.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                stepButton("minus", action: onDecrement, title: "Decrease")
                stepButton("plus", action: onIncrement, title: "Increase")
            }
        }
        .sensoryFeedback(.selection, trigger: taps) { _, _ in SettingsStore.shared.workoutHaptics }
        .accessibilityRepresentation {
            Stepper(onIncrement: onIncrement.map { action in { perform(action) } },
                    onDecrement: onDecrement.map { action in { perform(action) } }) { label }
        }
    }

    private func stepButton(_ symbol: String, action: (() -> Void)?, title: String) -> some View {
        Button {
            if let action { perform(action) }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(LiteweightTheme.primaryText)
                .frame(width: 40, height: 40)
                .background(LiteweightTheme.field, in: Circle())
                .frame(width: LiteweightTheme.controlHeight, height: LiteweightTheme.controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(action == nil)
        .accessibilityLabel(title)
    }

    private func perform(_ action: () -> Void) {
        action()
        taps += 1
    }
}

// MARK: - Zoom navigation

/// The tapped row grows into the page it opens and shrinks back on close (iOS 18).
/// Older iOS and Reduce Motion keep the standard push.
private struct LiteweightZoomSource<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct LiteweightZoomDestination<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    func liteweightZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        modifier(LiteweightZoomSource(id: id, namespace: namespace))
    }

    func liteweightZoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        modifier(LiteweightZoomDestination(id: id, namespace: namespace))
    }
}

// MARK: - Muscle figure

/// A workout's muscles, front and back, each in its group's color: primary movers
/// solid, helpers faint. Leads History and Last Workout rows (the owner's request,
/// in place of the group chips and tile). Pass the exercises with completed sets.
struct LiteweightMuscleFigure: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @Environment(\.self) private var environment
    @Environment(\.displayScale) private var displayScale
    let exerciseIDs: [UUID]

    static let height: CGFloat = 52
    /// MuscleMap draws each side in a 727 × 1280 box.
    static let aspect: CGFloat = 727 / 1280

    private struct Highlights {
        var primary: [String: [Muscle]] = [:]
        var secondary: [String: [Muscle]] = [:]
    }

    private struct Key: Hashable {
        let side: BodySide
        let primary: [String: [Muscle]]
        let secondary: [String: [Muscle]]
        let colorScheme: ColorScheme
        let colorSchemeContrast: ColorSchemeContrast
        let displayScale: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    @MainActor private enum PictureCache {
        static var images: [Key: UIImage] = [:]
    }

    private var highlights: Highlights {
        var result = Highlights()
        var seen = Set<Muscle>()
        // A muscle the group table doesn't name takes its exercise's group when it's a primary mover.
        func add(_ names: [String], fallback: String?, to keyPath: WritableKeyPath<Highlights, [String: [Muscle]]>) {
            for name in names {
                guard let muscle = liteweightMapMuscle(name), !seen.contains(muscle),
                      let group = Exercise.muscleGroup(for: name.lowercased()) ?? fallback,
                      LiteweightPalette.hasMuscleColor(group) else { continue }
                seen.insert(muscle)
                result[keyPath: keyPath][group, default: []].append(muscle)
            }
        }
        let exercises = exerciseIDs.compactMap { exerciseStore.exercisesByUUID[$0] }
        for exercise in exercises { add(exercise.primaryMuscle, fallback: exercise.muscleGroup, to: \.primary) }
        for exercise in exercises { add(exercise.secondaryMuscle, fallback: nil, to: \.secondary) }
        return result
    }

    var body: some View {
        let highlights = highlights
        HStack(spacing: 1) {
            cachedFigure(.front, highlights)
                .frame(width: Self.height * Self.aspect, height: Self.height)
            cachedFigure(.back, highlights)
                .frame(width: Self.height * Self.aspect, height: Self.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func cachedFigure(_ side: BodySide, _ highlights: Highlights) -> some View {
        if let image = picture(side, highlights) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            figure(side, highlights)
        }
    }

    @MainActor private func picture(_ side: BodySide, _ highlights: Highlights) -> UIImage? {
        let key = Key(
            side: side,
            primary: highlights.primary.mapValues { $0.sorted { $0.rawValue < $1.rawValue } },
            secondary: highlights.secondary.mapValues { $0.sorted { $0.rawValue < $1.rawValue } },
            colorScheme: environment.colorScheme,
            colorSchemeContrast: environment.colorSchemeContrast,
            displayScale: displayScale,
            width: Self.height * Self.aspect,
            height: Self.height
        )
        if let image = PictureCache.images[key] { return image }
        let renderer = ImageRenderer(content: figure(side, highlights)
            .frame(width: key.width, height: key.height))
        renderer.scale = displayScale
        renderer.isOpaque = false
        guard let image = renderer.uiImage else { return nil }
        if PictureCache.images.count >= 120 { PictureCache.images.removeAll(keepingCapacity: true) }
        PictureCache.images[key] = image
        return image
    }

    private func figure(_ side: BodySide, _ highlights: Highlights) -> some View {
        let style = BodyViewStyle(
            defaultFillColor: Color(Color(.tertiaryLabel).opacity(0.35).resolve(in: environment)),
            strokeColor: Color(Color(.separator).resolve(in: environment)),
            strokeWidth: 0.5,
            selectionColor: Color(LiteweightTheme.accent.resolve(in: environment)),
            selectionStrokeColor: Color(LiteweightTheme.accent.resolve(in: environment)),
            selectionStrokeWidth: 1,
            headColor: Color(Color(.tertiaryLabel).opacity(0.45).resolve(in: environment)),
            hairColor: Color(Color(.quaternaryLabel).resolve(in: environment))
        )
        var view = BodyView(gender: .male, side: side, style: style)
            .decorative()
        for (group, muscles) in highlights.secondary {
            view = view.highlight(muscles, color: Color(LiteweightTheme.muscle(group).resolve(in: environment)), opacity: 0.42)
        }
        for (group, muscles) in highlights.primary {
            view = view.highlight(muscles, color: Color(LiteweightTheme.muscle(group).resolve(in: environment)))
        }
        return view
    }
}
