//
//  HomeWeekViews.swift
//  liteweight
//

import SwiftUI
import Charts
import WorkoutDataKit

// MARK: - Home preferences

/// The cards Home can show. Each This Week view is a card of its own, so any number of them can sit on Home together.
enum HomeSection: String, CaseIterable, Identifiable {
    case rings, pace, muscleWeek, bars, calendar, recent, muscles, body, pinned, records, nextWorkout, trainingTrend, muscleLoad

    static let cardsKey = "home.cards"
    static let defaultCards: [HomeSection] = [.rings, .calendar, .muscles, .body, .pinned]

    /// Build 71 stored one This Week style plus a section order and a hidden list.
    static let legacyStyleKey = "home.weekStyle"
    static let legacyOrderKey = "home.sectionOrder"
    static let legacyHiddenKey = "home.hiddenSections"

    var id: String { rawValue }

    /// The cards that draw this week; the first one on Home is titled This Week and shows its date range.
    var isWeekCard: Bool { [.rings, .pace, .muscleWeek, .bars].contains(self) }

    var title: String {
        switch self {
        case .rings: return "Rings"
        case .pace: return "Pace"
        case .muscleWeek: return "Muscle Week"
        case .bars: return "Daily Volume"
        case .calendar: return "Last 4 Weeks"
        case .recent: return "Recent Training"
        case .muscles: return "Muscle Focus"
        case .body: return "Body"
        case .pinned: return "Pinned Charts"
        case .records: return "Recent Records"
        case .nextWorkout: return "Next Workout"
        case .trainingTrend: return "Training Trend"
        case .muscleLoad: return "Muscle Load"
        }
    }

    var summary: String {
        switch self {
        case .rings: return "Volume, sets and workouts close at your goals, or at last week's totals."
        case .pace: return "Your running volume against last week's line."
        case .muscleWeek: return "Which muscle groups you trained on each day."
        case .bars: return "Volume for each day of the week."
        case .calendar: return "The days you trained over the last four weeks."
        case .recent: return "Your latest workouts, ready to repeat."
        case .muscles: return "Weekly sets for each muscle group against your target."
        case .body: return "Body weight trend and measurements."
        case .pinned: return "Charts you pin from an exercise. Shows once one is pinned."
        case .records: return "New personal records from the last 30 days."
        case .nextWorkout: return "The saved workout that's up next, ready to start."
        case .trainingTrend: return "Duration, volume or reps by week or month."
        case .muscleLoad: return "Muscles you trained over the last 7 days."
        }
    }

    var systemImage: String {
        switch self {
        case .rings: return "circle.circle"
        case .pace: return "chart.line.uptrend.xyaxis"
        case .muscleWeek: return "circle.grid.3x3"
        case .bars: return "chart.bar"
        case .calendar: return "calendar"
        case .recent: return "clock.arrow.circlepath"
        case .muscles: return "figure.strengthtraining.traditional"
        case .body: return "figure"
        case .pinned: return "pin"
        case .records: return "trophy"
        case .nextWorkout: return "list.bullet.clipboard"
        case .trainingTrend: return "chart.bar.xaxis"
        case .muscleLoad: return "figure.arms.open"
        }
    }

    /// Cards with settings of their own get a pencil beside their title and an Edit item in
    /// their hold menu; Edit Home only adds, removes and reorders cards (build 117).
    var isEditable: Bool { [.rings, .muscles, .body, .pinned].contains(self) }

    var editTitle: String { "Edit \(title)" }

    /// The saved cards in order, merging Body Weight into Body before skipping unknown and repeated names.
    /// An empty string means Home has no cards.
    static func decode(_ stored: String) -> [HomeSection] {
        var seen = Set<HomeSection>()
        return stored.split(separator: ",")
            .compactMap { HomeSection(rawValue: canonicalName(String($0))) }
            .filter { seen.insert($0).inserted }
    }

    private static func canonicalName(_ name: String) -> String {
        name == "bodyWeight" ? "body" : name
    }

    static func encode<S: Sequence>(_ cards: S) -> String where S.Element == HomeSection {
        cards.map(\.rawValue).joined(separator: ",")
    }

    /// The saved cards, or the build 71 layout carried over, or the default layout.
    static func resolve(_ stored: String?, defaults: UserDefaults = .standard) -> [HomeSection] {
        if let stored { return decode(stored) }
        return migrated(
            style: defaults.string(forKey: legacyStyleKey),
            order: defaults.string(forKey: legacyOrderKey),
            hidden: defaults.string(forKey: legacyHiddenKey)
        )
    }

    /// Build 71's layout as cards: its single This Week section becomes the card for the style it showed.
    static func migrated(style: String?, order: String?, hidden: String?) -> [HomeSection] {
        guard style != nil || order != nil || hidden != nil else { return defaultCards }
        let legacy = ["week", "calendar", "recent", "muscles", "body", "pinned"]
        let hiddenNames = Set((hidden ?? "").split(separator: ",").map { canonicalName(String($0)) })
        var names = (order ?? "").split(separator: ",").map { canonicalName(String($0)) }.filter { legacy.contains($0) }
        names += legacy.filter { !names.contains($0) }
        let weekCard: HomeSection = switch style {
        case "pace": .pace
        case "muscles": .muscleWeek
        case "bars": .bars
        default: .rings
        }
        var seen = Set<HomeSection>()
        return names.filter { !hiddenNames.contains($0) }
            .compactMap { $0 == "week" ? weekCard : HomeSection(rawValue: $0) }
            .filter { seen.insert($0).inserted }
    }
}

/// The weekly sets per muscle that Muscle Focus shades: the All Muscles range, and any group's own range.
enum WeeklySetTarget {
    static let lowKey = "home.weeklySetTargetLow"
    static let highKey = "home.weeklySetTargetHigh"
    /// Groups with a range of their own, as "legs:12-20,abdominals:6-10" (build 117).
    static let groupsKey = "home.weeklySetTargetsByGroup"
    static let defaultLow = 10
    static let defaultHigh = 20

    static func decode(_ stored: String) -> [String: ClosedRange<Int>] {
        var ranges: [String: ClosedRange<Int>] = [:]
        for entry in stored.split(separator: ",") {
            let parts = entry.split(separator: ":")
            guard parts.count == 2, HomeWeekSummary.muscleGroups.contains(String(parts[0])) else { continue }
            let bounds = parts[1].split(separator: "-").compactMap { Int($0) }
            guard bounds.count == 2, bounds[0] >= 1, bounds[1] > bounds[0] else { continue }
            ranges[String(parts[0])] = bounds[0]...bounds[1]
        }
        return ranges
    }

    static func encode(_ ranges: [String: ClosedRange<Int>]) -> String {
        HomeWeekSummary.muscleGroups.compactMap { group in
            ranges[group].map { "\(group):\($0.lowerBound)-\($0.upperBound)" }
        }.joined(separator: ",")
    }
}

/// Each ring's goal on Home. Zero, the default, follows last week's total; anything else is the user's own goal (build 117).
struct WeekRingGoals: Equatable {
    static let volumeKey = "home.ringGoal.volume"
    static let setsKey = "home.ringGoal.sets"
    static let workoutsKey = "home.ringGoal.workouts"

    /// Kilograms.
    var volume = 0.0
    var sets = 0
    var workouts = 0

    var followsLastWeek: Bool { self == WeekRingGoals() }

    func volumeGoal(_ summary: HomeWeekSummary) -> Double { volume > 0 ? volume : summary.lastVolume }
    func setsGoal(_ summary: HomeWeekSummary) -> Int { sets > 0 ? sets : summary.lastSets }
    func workoutsGoal(_ summary: HomeWeekSummary) -> Int { workouts > 0 ? workouts : summary.lastWorkouts }
}

/// The measurements Body lists under its weight chart (build 117).
enum HomeBodyRows {
    static let key = "home.bodyRows"
    static let defaultKinds: [BodyMeasurementKind] = [.bodyFat, .waist]
    static let choices = BodyMeasurementKind.allCases.filter { $0 != .bodyWeight }

    static func decode(_ stored: String?) -> [BodyMeasurementKind] {
        guard let stored else { return defaultKinds }
        let kinds = Set(stored.split(separator: ",").compactMap { BodyMeasurementKind(rawValue: String($0)) })
        return choices.filter(kinds.contains)
    }

    static func encode(_ kinds: [BodyMeasurementKind]) -> String {
        kinds.map(\.rawValue).joined(separator: ",")
    }
}

/// Spoken Home metrics use full units rather than the compact chart labels.
enum HomeCardSpeech {
    static func number(_ value: Double, maximumFractionDigits: Int = 1) -> String {
        let magnitude = abs(value)
        let scale: (Double, String)
        switch magnitude {
        case 1_000_000_000...: scale = (1_000_000_000, " billion")
        case 1_000_000...: scale = (1_000_000, " million")
        case 1_000...: scale = (1_000, " thousand")
        default: scale = (1, "")
        }
        return (value / scale.0).formatted(.number.precision(.fractionLength(0...maximumFractionDigits))) + scale.1
    }

    static func count(_ value: Int, singular: String, plural: String) -> String {
        "\(number(Double(value))) \(value == 1 ? singular : plural)"
    }

    static func weightUnit(_ unit: WeightUnit) -> String {
        unit == .metric ? "kilograms" : "pounds"
    }

    static func displayWeight(_ value: Double, unit: WeightUnit) -> String {
        "\(number(value)) \(weightUnit(unit))"
    }

    static func weight(_ kilograms: Double, unit: WeightUnit) -> String {
        displayWeight(WeightUnit.convert(weight: kilograms, from: .metric, to: unit), unit: unit)
    }

    static func duration(_ seconds: TimeInterval, includesSeconds: Bool = false) -> String {
        let minutes = max(Int(seconds / 60), 0)
        let remainingSeconds = max(Int(seconds), 0) % 60
        guard minutes > 0 else {
            return includesSeconds ? count(remainingSeconds, singular: "second", plural: "seconds") : "less than 1 minute"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return [hours > 0 ? count(hours, singular: "hour", plural: "hours") : nil,
                remaining > 0 ? count(remaining, singular: "minute", plural: "minutes") : nil,
                includesSeconds && remainingSeconds > 0 ? count(remainingSeconds, singular: "second", plural: "seconds") : nil]
            .compactMap { $0 }.joined(separator: " ")
    }
}

/// Display-only regions are one element; interactive siblings remain reachable.
struct HomeCardAccessibilitySummary: ViewModifier {
    let title: String
    let value: String
    var isSummary = false
    /// The card's own edit, since the summary hides the pencil inside it.
    var edit: (title: String, action: () -> Void)?

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAddTraits(isSummary ? .isSummaryElement : [])
            .accessibilitySortPriority(1)
            .accessibilityActions {
                if let edit {
                    Button(edit.title, action: edit.action)
                }
            }
    }
}

struct HomeCardAccessibilityContainer: ViewModifier {
    var isSingleElement = false

    func body(content: Content) -> some View {
        if isSingleElement {
            // Do not replace an existing display-only summary's ignore behavior.
            content.accessibilitySortPriority(0)
        } else {
            content.accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Week summary

/// This week's training beside last week's, plus per-muscle detail, for the This Week card and Muscle Focus.
struct HomeWeekSummary {
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let volume: Double
        let isToday: Bool
        let isFuture: Bool
    }

    /// The groups Home tracks, in the order Muscle Week lists them. Cardio and unmapped exercises are left out.
    static let muscleGroups = ["legs", "chest", "back", "shoulders", "arms", "abdominals"]

    static func displayName(_ group: String) -> String {
        group == "abdominals" ? "Core" : group.capitalized
    }

    var days: [Day] = []
    var lastWeekVolumes = Array(repeating: 0.0, count: 7)
    var workouts = 0
    var sets = 0
    var volume = 0.0
    var duration: TimeInterval = 0
    var lastWorkouts = 0
    var lastSets = 0
    var lastVolume = 0.0
    /// Sets for each tracked group on each day of this week.
    var muscleSets: [String: [Int]] = [:]
    /// The latest session that trained each tracked group, from all history.
    var lastTrained: [String: Date] = [:]
    /// Average sets a week for each tracked group over the last four weeks.
    var weeklyAverages: [String: Double] = [:]

    var todayIndex: Int { days.firstIndex(where: \.isToday) ?? max(days.count - 1, 0) }

    init() {}

    init(sessions: [TrainingSessionSnapshot], muscleGroup: (UUID) -> String?, now: Date = Date(), calendar: Calendar = .current) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: week.start),
              let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: now) else { return }
        let today = calendar.startOfDay(for: now)
        func dayIndex(_ date: Date, from start: Date) -> Int {
            calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? -1
        }

        var thisWeekVolumes = Array(repeating: 0.0, count: 7)
        var recentSets: [String: Int] = [:]
        for group in Self.muscleGroups { muscleSets[group] = Array(repeating: 0, count: 7) }

        for session in sessions where session.date <= now {
            let groups = session.exercises.map { item in (item.uuid.flatMap(muscleGroup) ?? "other", item.setCount) }
            for (group, _) in groups where Self.muscleGroups.contains(group) && session.date > (lastTrained[group] ?? .distantPast) {
                lastTrained[group] = session.date
            }
            if session.date >= fourWeeksAgo {
                for (group, count) in groups { recentSets[group, default: 0] += count }
            }
            if session.date >= week.start {
                let index = dayIndex(session.date, from: week.start)
                guard (0..<7).contains(index) else { continue }
                workouts += 1
                sets += session.setCount
                volume += session.volume
                duration += session.duration
                thisWeekVolumes[index] += session.volume
                for (group, count) in groups { muscleSets[group]?[index] += count }
            } else if session.date >= lastWeekStart {
                let index = dayIndex(session.date, from: lastWeekStart)
                guard (0..<7).contains(index) else { continue }
                lastWorkouts += 1
                lastSets += session.setCount
                lastVolume += session.volume
                lastWeekVolumes[index] += session.volume
            }
        }

        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let start = calendar.startOfDay(for: date)
            return Day(date: date, volume: thisWeekVolumes[offset], isToday: start == today, isFuture: start > today)
        }
        for group in Self.muscleGroups {
            weeklyAverages[group] = Double(recentSets[group] ?? 0) / 4
        }
    }

    /// Running totals at the end of each day, starting from zero before the week begins.
    static func runningTotals(_ volumes: [Double]) -> [Double] {
        volumes.reduce(into: [0]) { $0.append(($0.last ?? 0) + $1) }
    }
}

// MARK: - A · Rings

/// Three rings that close as this week catches up with last week, the way Fitness closes Move, Exercise and Stand.
struct WeekRingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var ringSize: CGFloat = 148
    @State private var hasAppeared = false
    let summary: HomeWeekSummary
    let unit: String
    let valueLabel: (Double) -> String
    var goals = WeekRingGoals()

    private struct Ring: Identifiable {
        let id: String
        let label: String
        let value: String
        let target: String?
        let unit: String?
        let progress: Double
        let isOwnGoal: Bool
        let tint: Color
        let track: Color
    }

    private var rings: [Ring] {
        let volumeGoal = goals.volumeGoal(summary)
        let setsGoal = goals.setsGoal(summary)
        let workoutsGoal = goals.workoutsGoal(summary)
        return [
            Ring(id: "volume", label: "Volume", value: valueLabel(summary.volume),
                 target: volumeGoal > 0 ? valueLabel(volumeGoal) : nil, unit: unit,
                 progress: progress(summary.volume, of: volumeGoal), isOwnGoal: goals.volume > 0,
                 tint: LiteweightTheme.metricVolume, track: LiteweightTheme.metricVolumeContainer),
            Ring(id: "sets", label: "Sets", value: "\(summary.sets)",
                 target: setsGoal > 0 ? "\(setsGoal)" : nil, unit: nil,
                 progress: progress(Double(summary.sets), of: Double(setsGoal)), isOwnGoal: goals.sets > 0,
                 tint: LiteweightTheme.metricSets, track: LiteweightTheme.metricSetsContainer),
            Ring(id: "workouts", label: summary.workouts == 1 ? "Workout" : "Workouts", value: "\(summary.workouts)",
                 target: workoutsGoal > 0 ? "\(workoutsGoal)" : nil, unit: nil,
                 progress: progress(Double(summary.workouts), of: Double(workoutsGoal)), isOwnGoal: goals.workouts > 0,
                 tint: LiteweightTheme.accent, track: LiteweightTheme.accentSoft)
        ]
    }

    private func progress(_ value: Double, of target: Double) -> Double {
        guard target > 0 else { return value > 0 ? 1 : 0 }
        return min(value / target, 1)
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
        VStack(alignment: .leading, spacing: 14) {
            layout {
                ringStack
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rings) { ring in
                        ringMetric(ring)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            dayStrip
        }
        .animation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion), value: hasAppeared)
        .onAppear { hasAppeared = true }
    }

    func accessibilitySummary(weightUnit: WeightUnit) -> String {
        let volume = HomeCardSpeech.weight(summary.volume, unit: weightUnit)
        let volumeGoal = goals.volumeGoal(summary)
        let setsGoal = goals.setsGoal(summary)
        let workoutsGoal = goals.workoutsGoal(summary)
        let volumeTarget = volumeGoal > 0
            ? "Volume \(HomeCardSpeech.number(WeightUnit.convert(weight: summary.volume, from: .metric, to: weightUnit))) of \(HomeCardSpeech.weight(volumeGoal, unit: weightUnit))"
            : "Volume \(volume)"
        let sets = setsGoal > 0 ? "\(summary.sets) of \(setsGoal) sets" : HomeCardSpeech.count(summary.sets, singular: "set", plural: "sets")
        let workouts = workoutsGoal > 0 ? "\(summary.workouts) of \(workoutsGoal) workouts" : HomeCardSpeech.count(summary.workouts, singular: "workout", plural: "workouts")
        let meaning = !goals.followsLastWeek
            ? "Each ring closes when you reach its goal."
            : summary.lastWorkouts > 0
            ? "Each ring closes when you match last week."
            : "Nothing was logged last week, so any training closes a ring."
        return "\(volumeTarget), \(sets), \(workouts). \(meaning)"
    }

    private var ringStack: some View {
        let size = min(ringSize, 200)
        let width = size * 0.107
        let step = width + size * 0.024
        return ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let diameter = size - CGFloat(index) * step * 2
                ZStack {
                    Circle()
                        .inset(by: width / 2)
                        .stroke(ring.track, lineWidth: width)
                    Circle()
                        .inset(by: width / 2)
                        .trim(from: 0, to: hasAppeared || reduceMotion ? ring.progress : 0)
                        .stroke(ring.tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: diameter, height: diameter)
            }
        }
        .frame(width: size, height: size)
    }

    private func ringMetric(_ ring: Ring) -> some View {
        let suffix = [ring.target.map { " / " + $0 }, ring.unit.map { " " + $0 }].compactMap { $0 }.joined()
        return VStack(alignment: .leading, spacing: 1) {
            Text(ring.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ring.tint)
                .textCase(.uppercase)
            (Text(ring.value).font(.liteweightMetric(.title2, weight: .bold)).foregroundColor(LiteweightTheme.primaryText)
             + Text(suffix).font(.subheadline.weight(.medium)).foregroundColor(LiteweightTheme.secondaryText))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(reduceMotion ? .opacity : .numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ring.label)
        .accessibilityValue("\(ring.value)\(ring.target.map { " of \($0)" } ?? "")\(ring.unit.map { " \($0)" } ?? ""), \(Int((ring.progress * 100).rounded())) percent of \(ring.isOwnGoal ? "your goal" : "last week")")
    }

    private var dayStrip: some View {
        let best = summary.days.map(\.volume).max() ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(summary.days) { day in
                    VStack(spacing: 6) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption.weight(day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday ? LiteweightTheme.accent : LiteweightTheme.secondaryText)
                        ZStack {
                            Circle()
                                .inset(by: 2.5)
                                .stroke(day.volume > 0 ? LiteweightTheme.metricVolumeContainer : LiteweightTheme.tertiaryFill, lineWidth: 5)
                            if day.volume > 0, best > 0 {
                                Circle()
                                    .inset(by: 2.5)
                                    .trim(from: 0, to: hasAppeared || reduceMotion ? day.volume / best : 0)
                                    .stroke(LiteweightTheme.metricVolume, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                        }
                        .frame(width: 28, height: 28)
                        .opacity(day.isFuture ? 0.5 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue(day.volume > 0 ? "\(valueLabel(day.volume)) \(unit)" : day.isFuture ? "Upcoming" : "Rest day")
                }
            }
        }
    }
}

// MARK: - B · Pace

/// Running volume this week over last week's line, so the card says whether the week is on pace.
struct WeekPaceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    let summary: HomeWeekSummary
    let unit: String
    let valueLabel: (Double) -> String

    private struct Point: Identifiable {
        var id: String { "\(series)-\(x)" }
        let series: String
        let x: Double
        let y: Double
    }

    private var thisWeek: [Double] { HomeWeekSummary.runningTotals(summary.days.map(\.volume)) }
    private var lastWeek: [Double] { HomeWeekSummary.runningTotals(summary.lastWeekVolumes) }
    private var todayEnd: Int { summary.todayIndex + 1 }

    private var points: [Point] {
        let grow = hasAppeared || reduceMotion ? 1.0 : 0.0
        let last = lastWeek.enumerated().map { Point(series: "Last week", x: Double($0.offset), y: $0.element * grow) }
        let this = thisWeek.prefix(todayEnd + 1).enumerated().map { Point(series: "This week", x: Double($0.offset), y: $0.element * grow) }
        return last + this
    }

    private var yMax: Double {
        let top = max(lastWeek.last ?? 0, thisWeek.last ?? 0)
        return top > 0 ? top * 1.1 : 1
    }

    private var weekdayName: String {
        guard summary.days.indices.contains(summary.todayIndex) else { return "" }
        return summary.days[summary.todayIndex].date.formatted(.dateTime.weekday(.wide))
    }

    /// How far ahead of or behind last week's running total this week is, at the end of the same weekday.
    private var comparison: (difference: Double, detail: String) {
        let now = thisWeek[min(todayEnd, thisWeek.count - 1)]
        let then = lastWeek[min(todayEnd, lastWeek.count - 1)]
        let difference = now - then
        guard summary.lastVolume > 0 else {
            return (abs(difference), "Nothing logged last week")
        }
        guard abs(difference) > max(then, 1) * 0.03 else {
            return (abs(difference), "even with last \(weekdayName)")
        }
        return difference > 0
            ? (difference, "ahead of last \(weekdayName)")
            : (abs(difference), "behind last \(weekdayName)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                let pace = comparison
                LiteweightMetricValue(value: valueLabel(pace.difference), unit: unit,
                                style: .title, weight: .bold, tint: LiteweightTheme.primaryText)
                Text(pace.detail)
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)

            chart

            HStack(spacing: 18) {
                legendItem(dashed: false, title: "This week")
                legendItem(dashed: true, title: "Last week · \(valueLabel(summary.lastVolume)) \(unit)")
            }
            .font(.footnote)
            .foregroundStyle(LiteweightTheme.secondaryText)
            .accessibilityHidden(true)
        }
        .animation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion), value: hasAppeared)
        .onAppear { hasAppeared = true }
    }

    private var chart: some View {
        let todayX = Double(todayEnd)
        return Chart {
            if todayX < 7 {
                RectangleMark(xStart: .value("Day", todayX), xEnd: .value("Day", 7.0))
                    .foregroundStyle(LiteweightTheme.tertiaryFill.opacity(0.5))
            }
            ForEach(points) { point in
                LineMark(x: .value("Day", point.x), y: .value("Volume", point.y), series: .value("Week", point.series))
                    .foregroundStyle(point.series == "This week" ? LiteweightTheme.metricVolume : LiteweightTheme.tertiaryText)
                    .lineStyle(point.series == "This week"
                               ? StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                               : StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [4, 4]))
            }
            if hasAppeared || reduceMotion, thisWeek.indices.contains(todayEnd), lastWeek.indices.contains(todayEnd) {
                RuleMark(x: .value("Day", todayX),
                         yStart: .value("Volume", lastWeek[todayEnd]),
                         yEnd: .value("Volume", thisWeek[todayEnd]))
                    .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round))
                    .foregroundStyle(LiteweightTheme.metricVolume.opacity(0.25))
                PointMark(x: .value("Day", todayX), y: .value("Volume", thisWeek[todayEnd]))
                    .symbolSize(120)
                    .foregroundStyle(LiteweightTheme.surface)
                PointMark(x: .value("Day", todayX), y: .value("Volume", thisWeek[todayEnd]))
                    .symbolSize(56)
                    .foregroundStyle(LiteweightTheme.metricVolume)
            }
        }
        .chartXScale(domain: 0...7)
        .chartYScale(domain: 0...yMax)
        .liteweightValueAxis(.automatic(desiredCount: 3), label: valueLabel)
        .chartXAxis {
            AxisMarks(values: (0..<7).map { Double($0) + 0.5 }) { value in
                AxisValueLabel {
                    if let raw = value.as(Double.self), summary.days.indices.contains(Int(raw)) {
                        let day = summary.days[Int(raw)]
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption.weight(day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday ? LiteweightTheme.accent : LiteweightTheme.secondaryText)
                    }
                }
            }
        }
        .frame(height: 150)
    }

    func accessibilitySummary(weightUnit: WeightUnit) -> String {
        let pace = comparison
        let description = summary.lastVolume > 0
            ? "\(HomeCardSpeech.weight(pace.difference, unit: weightUnit)) \(pace.detail)"
            : pace.detail
        return "This week's running volume compared with last week. \(HomeCardSpeech.weight(summary.volume, unit: weightUnit)) so far. \(description). Last week finished at \(HomeCardSpeech.weight(summary.lastVolume, unit: weightUnit))."
    }

    private func legendItem(dashed: Bool, title: String) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1.5))
                path.addLine(to: CGPoint(x: 16, y: 1.5))
            }
            .stroke(dashed ? LiteweightTheme.tertiaryText : LiteweightTheme.metricVolume,
                    style: StrokeStyle(lineWidth: dashed ? 2 : 3, lineCap: dashed ? .butt : .round, dash: dashed ? [4, 4] : []))
            .frame(width: 16, height: 3)
            Text(title)
        }
    }
}

// MARK: - C · Muscles

/// Each tracked muscle group by day of the week, dot size showing sets, with how long since each was trained.
struct MuscleWeekGrid: View {
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .subheadline) private var nameWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .footnote) private var lastWidth: CGFloat = 46
    let summary: HomeWeekSummary
    var now = Date()

    private var groups: [String] { HomeWeekSummary.muscleGroups }

    private func daysSince(_ group: String) -> Int? {
        guard let date = summary.lastTrained[group] else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
    }

    private func lastText(_ group: String) -> String {
        guard let days = daysSince(group), days <= 60 else { return "—" }
        return days == 0 ? "Today" : "\(days)d"
    }

    private func dotDiameter(_ sets: Int) -> CGFloat {
        min(7 * sqrt(CGFloat(sets)), rowHeight - 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                headerRow
                ForEach(Array(groups.enumerated()), id: \.element) { index, group in
                    row(group, isLast: index == groups.count - 1)
                }
            }

            if let insight = restedInsight {
                Text(insight)
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sizeKey
        }
    }

    var accessibilitySummary: String {
        let details = groups.map { group in
            "\(HomeWeekSummary.displayName(group)): \(accessibilityValue(group, sets: summary.muscleSets[group] ?? []))"
        }.joined(separator: " ")
        return "Muscle groups trained each day this week; larger dots mean more sets. \(details)" + (restedInsight.map { " " + $0 } ?? "")
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: nameWidth, height: 1)
            ForEach(summary.days) { day in
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption.weight(day.isToday ? .bold : .regular))
                    .foregroundStyle(day.isToday ? LiteweightTheme.accent : LiteweightTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(todayColumn(day, top: true, bottom: false))
            }
            Text("Last")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LiteweightTheme.secondaryText)
                .textCase(.uppercase)
                .frame(width: lastWidth, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }

    private func row(_ group: String, isLast: Bool) -> some View {
        let sets = summary.muscleSets[group] ?? []
        let last = lastText(group)
        return HStack(spacing: 0) {
            Text(HomeWeekSummary.displayName(group))
                .font(.subheadline)
                .foregroundStyle(LiteweightTheme.primaryText)
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)
            ForEach(Array(summary.days.enumerated()), id: \.element.id) { index, day in
                let count = sets.indices.contains(index) ? sets[index] : 0
                ZStack {
                    if count > 0 {
                        Circle()
                            .fill(LiteweightTheme.metricSets)
                            .frame(width: dotDiameter(count), height: dotDiameter(count))
                    } else {
                        Circle()
                            .fill(LiteweightTheme.tertiaryText.opacity(day.isFuture ? 0.25 : 0.5))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: rowHeight)
                .background(todayColumn(day, top: false, bottom: isLast))
            }
            Text(last)
                .font(.footnote.weight(last == "Today" ? .semibold : .regular))
                .foregroundStyle(last == "Today" ? LiteweightTheme.primaryText : LiteweightTheme.secondaryText)
                .monospacedDigit()
                .frame(width: lastWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeWeekSummary.displayName(group))
        .accessibilityValue(accessibilityValue(group, sets: sets))
    }

    @ViewBuilder
    private func todayColumn(_ day: HomeWeekSummary.Day, top: Bool, bottom: Bool) -> some View {
        if day.isToday {
            UnevenRoundedRectangle(
                topLeadingRadius: top ? 12 : 0, bottomLeadingRadius: bottom ? 12 : 0,
                bottomTrailingRadius: bottom ? 12 : 0, topTrailingRadius: top ? 12 : 0,
                style: .continuous
            )
            .fill(LiteweightTheme.tertiaryFill)
        }
    }

    private func accessibilityValue(_ group: String, sets: [Int]) -> String {
        let trained = summary.days.enumerated().compactMap { index, day -> String? in
            guard sets.indices.contains(index), sets[index] > 0 else { return nil }
            return "\(sets[index]) \(sets[index] == 1 ? "set" : "sets") \(day.date.formatted(.dateTime.weekday(.wide)))"
        }
        let week = trained.isEmpty ? "No sets this week" : trained.joined(separator: ", ")
        guard let days = daysSince(group), days <= 60 else { return week + ". Not trained recently." }
        return week + ". Last trained " + (days == 0 ? "today." : "\(days) \(days == 1 ? "day" : "days") ago.")
    }

    /// Names the groups that have rested longest, so the card suggests what to train next.
    private var restedInsight: String? {
        guard !summary.lastTrained.isEmpty else { return nil }
        let rested = groups.map { ($0, daysSince($0) ?? Int.max) }
        guard let longest = rested.map(\.1).max(), longest >= 2 else { return nil }
        let names = rested.filter { $0.1 == longest }.map { HomeWeekSummary.displayName($0.0).lowercased() }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        let subject = list.prefix(1).uppercased() + list.dropFirst()
        let verb = names.count == 1 ? "is" : "are"
        guard longest <= 60 else { return "\(subject) \(verb) missing from your recent training." }
        let when: String
        if longest < 7, let group = rested.first(where: { $0.1 == longest })?.0, let date = summary.lastTrained[group] {
            when = date.formatted(.dateTime.weekday(.wide))
        } else {
            when = "\(longest) days ago"
        }
        return "\(subject) \(verb) the most rested, last trained \(when)."
    }

    @ViewBuilder
    private var sizeKey: some View {
        let counts = summary.muscleSets.values.flatMap { $0 }.filter { $0 > 0 }
        if let low = counts.min(), let high = counts.max() {
            HStack(spacing: 6) {
                Text("Dot size shows sets:")
                Circle().fill(LiteweightTheme.metricSets).frame(width: dotDiameter(low), height: dotDiameter(low))
                Text("\(low)").monospacedDigit()
                if high != low {
                    Circle().fill(LiteweightTheme.metricSets).frame(width: dotDiameter(high), height: dotDiameter(high))
                    Text("\(high)").monospacedDigit()
                }
            }
            .font(.footnote)
            .foregroundStyle(LiteweightTheme.secondaryText)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - E · Weekly sets

/// Average weekly sets for each tracked muscle group over the last four weeks, against the user's target range.
struct WeeklySetsChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var nameWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 40
    @State private var hasAppeared = false
    let averages: [String: Double]
    /// Sets logged since the week began, drawn as a thin bar over the wide pale
    /// four-week-average bar so a row reads as this week filling toward a usual week (build 117).
    var thisWeek: [String: Int] = [:]
    /// The All Muscles range; it labels the axis.
    let target: ClosedRange<Int>
    /// Groups with a range of their own, each shading its own band (build 117).
    var groupTargets: [String: ClosedRange<Int>] = [:]

    private struct Row: Identifiable {
        var id: String { group }
        let group: String
        let sets: Double
        let thisWeek: Int
        let target: ClosedRange<Int>
    }

    private var rows: [Row] {
        HomeWeekSummary.muscleGroups
            .map { Row(group: $0, sets: averages[$0] ?? 0, thisWeek: thisWeek[$0] ?? 0, target: groupTargets[$0] ?? target) }
            .sorted { $0.sets > $1.sets }
    }

    private var scaleMax: Double {
        let highest = rows.map { max($0.sets, Double($0.thisWeek), Double($0.target.upperBound) * 1.2) }.max() ?? 0
        return max(Double(target.upperBound) * 1.2, highest)
    }

    private var reaching: Int { rows.filter { $0.sets >= Double($0.target.lowerBound) }.count }

    private var sharesOneTarget: Bool { groupTargets.values.allSatisfy { $0 == target } }

    static func format(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(sets == sets.rounded() ? 0 : 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LiteweightChartHeader(
                caption: "Avg sets a week · last 4 weeks",
                value: LiteweightChartText.value("\(reaching) of \(rows.count)", unit: "groups", tint: LiteweightTheme.metricSets, style: .title),
                detail: sharesOneTarget ? "reach \(target.lowerBound) sets a week" : "reach their target"
            )

            VStack(spacing: 0) {
                axisRow
                ForEach(rows) { row in
                    barRow(row)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legendItems }
                VStack(alignment: .leading, spacing: 6) { legendItems }
            }
            .font(.footnote)
            .foregroundStyle(LiteweightTheme.secondaryText)
            .accessibilityHidden(true)
        }
        .animation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion), value: hasAppeared)
        .onAppear { hasAppeared = true }
    }

    /// Group colors vary by row, so the legend explains the two bars by shape in a neutral tint.
    @ViewBuilder
    private var legendItems: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(LiteweightTheme.secondaryText.opacity(Self.averageOpacity))
                .frame(width: 18, height: Self.averageThickness)
            Text("Avg")
        }
        HStack(spacing: 6) {
            Capsule()
                .fill(LiteweightTheme.secondaryText)
                .frame(width: 18, height: Self.weekThickness)
            Text("This week")
        }
        HStack(spacing: 6) {
            bandShape.frame(width: 14, height: 12)
            Text(sharesOneTarget ? "Target, \(target.lowerBound)–\(target.upperBound) sets" : "Target")
        }
    }

    private static let averageThickness: CGFloat = 12
    private static let weekThickness: CGFloat = 6
    private static let averageOpacity = 0.4

    /// A bar's length on the axis; any sets at all show at least a dot as wide as the bar is tall.
    private func barLength(_ sets: Double, width: CGFloat, thickness: CGFloat) -> CGFloat {
        guard hasAppeared || reduceMotion, sets > 0 else { return 0 }
        return max(width * sets / scaleMax, thickness)
    }

    private var bandShape: some View {
        Rectangle()
            .fill(LiteweightTheme.tertiaryFill)
            .overlay(alignment: .leading) { dashedEdge }
            .overlay(alignment: .trailing) { dashedEdge }
    }

    private var dashedEdge: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: 1000))
        }
        .stroke(LiteweightTheme.outline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 1)
        .clipped()
    }

    /// At accessibility sizes the bars get the full width under each row's name and numbers,
    /// so the axis labels and column headers no longer collide.
    @ViewBuilder
    private var axisRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    columnHeaders
                }
                tickLabels
            }
            .accessibilityHidden(true)
        } else {
            HStack(spacing: 0) {
                Color.clear.frame(width: nameWidth, height: 1)
                tickLabels
                columnHeaders
            }
            .accessibilityHidden(true)
        }
    }

    private var tickLabels: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Text("0")
                Text("\(target.lowerBound)")
                    .position(x: width * Double(target.lowerBound) / scaleMax, y: 7)
                Text("\(target.upperBound)")
                    .position(x: width * Double(target.upperBound) / scaleMax, y: 7)
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(LiteweightTheme.secondaryText)
        }
        .frame(height: 16)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Avg")
                .lineLimit(1)
                .frame(width: valueWidth, alignment: .trailing)
            Text("This wk")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: valueWidth + 8, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(LiteweightTheme.secondaryText)
        .textCase(.uppercase)
    }

    @ViewBuilder
    private func barRow(_ row: Row) -> some View {
        let name = Text(HomeWeekSummary.displayName(row.group))
            .font(.body)
            .foregroundStyle(LiteweightTheme.primaryText)
            .lineLimit(1)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        name
                        Spacer(minLength: 8)
                        rowValues(row)
                    }
                    barTrack(row)
                        .frame(height: 20)
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 0) {
                    name
                        .frame(width: nameWidth, alignment: .leading)
                    barTrack(row)
                        .frame(height: rowHeight)
                    rowValues(row)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeWeekSummary.displayName(row.group))
        .accessibilityValue("\(row.thisWeek) \(row.thisWeek == 1 ? "set" : "sets") this week. Averages \(Self.format(row.sets)) sets a week, \(row.sets < Double(row.target.lowerBound) ? "below" : row.sets > Double(row.target.upperBound) ? "above" : "within") your \(row.target.lowerBound) to \(row.target.upperBound) target")
    }

    private func barTrack(_ row: Row) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let low = width * Double(row.target.lowerBound) / scaleMax
            let high = width * Double(row.target.upperBound) / scaleMax
            ZStack(alignment: .leading) {
                bandShape
                    .frame(width: high - low)
                    .offset(x: low)
                Capsule()
                    .fill(LiteweightTheme.muscle(row.group).opacity(Self.averageOpacity))
                    .frame(width: barLength(row.sets, width: width, thickness: Self.averageThickness), height: Self.averageThickness)
                Capsule()
                    .fill(LiteweightTheme.muscle(row.group))
                    .frame(width: barLength(Double(row.thisWeek), width: width, thickness: Self.weekThickness), height: Self.weekThickness)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
    }

    private func rowValues(_ row: Row) -> some View {
        HStack(spacing: 0) {
            Text(Self.format(row.sets))
                .font(.liteweightMetric(.body, weight: .semibold))
                .foregroundStyle(LiteweightTheme.secondaryText)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: row.sets))
                .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: row.sets)
                .frame(width: valueWidth, alignment: .trailing)
            Text("\(row.thisWeek)")
                .font(.liteweightMetric(.body, weight: .semibold))
                .foregroundStyle(row.thisWeek > 0 ? LiteweightTheme.primaryText : LiteweightTheme.tertiaryText)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(row.thisWeek)))
                .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: row.thisWeek)
                .frame(width: valueWidth + 8, alignment: .trailing)
        }
    }
}

// MARK: - Customize Home

/// Fitness-style Edit Summary for Home: the cards on Home in order and the cards that can be added.
/// A card's own settings live in its own editor (build 117).
struct CustomizeHomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HomeSection.cardsKey) private var storedCards: String?

    private var cards: [HomeSection] { HomeSection.resolve(storedCards) }
    private var available: [HomeSection] { HomeSection.allCases.filter { !cards.contains($0) } }

    private func update(_ change: (inout [HomeSection]) -> Void) {
        var updated = cards
        change(&updated)
        withAnimation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion)) {
            storedCards = HomeSection.encode(updated)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(cards) { card in
                        cardLabel(card)
                    }
                    .onMove { source, destination in update { $0.move(fromOffsets: source, toOffset: destination) } }
                    .onDelete { offsets in update { $0.remove(atOffsets: offsets) } }
                } header: {
                    Text("On Home")
                } footer: {
                    Text(cards.isEmpty
                         ? "Add a card below to fill Home."
                         : "Drag to change the order.")
                }

                if !available.isEmpty {
                    Section {
                        // Row IDs differ from On Home's, so an added card arrives as a new editable row
                        // rather than this row moved across, which would keep its non-editable cell.
                        ForEach(available, id: \.addRowID) { card in
                            Button {
                                update { $0.append(card) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(LiteweightTheme.success)
                                    cardLabel(card)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Add \(card.title)")
                            .accessibilityHint(card.summary)
                        }
                    } header: {
                        Text("Add to Home")
                    }
                }

                Section {
                    Button("Restore Default Layout") {
                        update { $0 = HomeSection.defaultCards }
                    }
                    .buttonStyle(.borderless)
                    .disabled(cards == HomeSection.defaultCards)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func cardLabel(_ card: HomeSection) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .foregroundStyle(LiteweightTheme.primaryText)
                Text(card.summary)
                    .font(.footnote)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: card.systemImage)
                .foregroundStyle(LiteweightTheme.accent)
        }
    }
}

private extension HomeSection {
    var addRowID: String { "add." + rawValue }
}

// MARK: - Card editors

/// Edit Rings: each ring follows last week's total or a goal of the user's own (build 117).
struct RingGoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeekRingGoals.volumeKey) private var volumeGoal = 0.0
    @AppStorage(WeekRingGoals.setsKey) private var setsGoal = 0
    @AppStorage(WeekRingGoals.workoutsKey) private var workoutsGoal = 0
    let summary: HomeWeekSummary
    let weightUnit: WeightUnit

    private var volumeStep: Double { weightUnit == .metric ? 500 : 1000 }

    private func displayVolume(_ kilograms: Double) -> Double {
        WeightUnit.convert(weight: kilograms, from: .metric, to: weightUnit).rounded()
    }

    private func volumeText(_ value: Double) -> String {
        "\(Int(value).formatted()) \(weightUnit.unit.symbol)"
    }

    var body: some View {
        NavigationStack {
            List {
                RingGoalSection(
                    title: "Volume", tint: LiteweightTheme.metricVolume,
                    lastWeek: summary.lastVolume > 0 ? volumeText(displayVolume(summary.lastVolume)) : nil,
                    goal: Binding(get: { volumeGoal > 0 ? displayVolume(volumeGoal) : 0 },
                                  set: { volumeGoal = $0 > 0 ? WeightUnit.convert(weight: $0, from: weightUnit, to: .metric) : 0 }),
                    start: summary.lastVolume > 0
                        ? max(volumeStep, (displayVolume(summary.lastVolume) / volumeStep).rounded() * volumeStep)
                        : volumeStep * 10,
                    step: volumeStep, range: volumeStep...1_000_000, format: volumeText)
                RingGoalSection(
                    title: "Sets", tint: LiteweightTheme.metricSets,
                    lastWeek: summary.lastSets > 0 ? "\(summary.lastSets) sets" : nil,
                    goal: Binding(get: { Double(setsGoal) }, set: { setsGoal = Int($0) }),
                    start: Double(summary.lastSets > 0 ? summary.lastSets : 30),
                    step: 1, range: 1...500, format: { "\(Int($0)) \(Int($0) == 1 ? "set" : "sets")" })
                RingGoalSection(
                    title: "Workouts", tint: LiteweightTheme.accent,
                    lastWeek: summary.lastWorkouts > 0 ? "\(summary.lastWorkouts) \(summary.lastWorkouts == 1 ? "workout" : "workouts")" : nil,
                    goal: Binding(get: { Double(workoutsGoal) }, set: { workoutsGoal = Int($0) }),
                    start: Double(summary.lastWorkouts > 0 ? summary.lastWorkouts : 3),
                    step: 1, range: 1...21, format: { "\(Int($0)) \(Int($0) == 1 ? "workout" : "workouts")" })
                Section {} footer: {
                    Text("Each ring closes when you reach its goal.")
                }
            }
            .navigationTitle("Rings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One ring in Edit Rings: Last Week or Custom, and the custom goal's stepper.
private struct RingGoalSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let tint: Color
    /// Last week's total, or nil when nothing was logged.
    let lastWeek: String?
    /// In display units; zero follows last week.
    @Binding var goal: Double
    let start: Double
    let step: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        Section {
            Picker("\(title) Goal", selection: Binding(
                get: { goal > 0 },
                set: { custom in
                    withAnimation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion)) {
                        goal = custom ? min(max(start, range.lowerBound), range.upperBound) : 0
                    }
                })) {
                Text("Last Week").tag(false)
                Text("Custom").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if goal > 0 {
                Stepper(value: $goal, in: range, step: step) {
                    LabeledContent("Goal") {
                        Text(format(goal))
                            .font(.liteweightMetric(.body, weight: .semibold))
                            .foregroundStyle(LiteweightTheme.primaryText)
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: goal))
                    }
                }
                .accessibilityValue(format(goal))
            } else {
                LabeledContent("Goal", value: lastWeek ?? "Any training")
            }
        } header: {
            Text(title)
                .foregroundStyle(tint)
        }
    }
}

/// Edit Muscle Focus: one weekly range for every group, and a range of its own for any group (build 117).
struct MuscleTargetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeeklySetTarget.lowKey) private var targetLow = WeeklySetTarget.defaultLow
    @AppStorage(WeeklySetTarget.highKey) private var targetHigh = WeeklySetTarget.defaultHigh
    @AppStorage(WeeklySetTarget.groupsKey) private var storedGroups = ""

    private var allRange: ClosedRange<Int> { targetLow...max(targetHigh, targetLow + 1) }

    private func rangeText(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound)–\(range.upperBound)"
    }

    var body: some View {
        let groups = WeeklySetTarget.decode(storedGroups)
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SetTargetEditor(group: nil)
                    } label: {
                        LabeledContent("All Muscles", value: rangeText(allRange))
                    }
                    ForEach(HomeWeekSummary.muscleGroups, id: \.self) { group in
                        NavigationLink {
                            SetTargetEditor(group: group)
                        } label: {
                            LabeledContent {
                                Text(rangeText(groups[group] ?? allRange))
                                    .foregroundStyle(groups[group] == nil ? LiteweightTheme.secondaryText : LiteweightTheme.primaryText)
                            } label: {
                                Label {
                                    Text(HomeWeekSummary.displayName(group))
                                } icon: {
                                    Circle()
                                        .fill(LiteweightTheme.muscle(group))
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                        .accessibilityValue("\(rangeText(groups[group] ?? allRange)) sets\(groups[group] == nil ? ", same as all muscles" : "")")
                    }
                } header: {
                    Text("Target Sets a Week")
                } footer: {
                    Text("Tap a muscle to give it a range of its own. Many lifters aim for 10–20 sets a week per muscle.")
                }
            }
            .navigationTitle("Muscle Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The At Least and At Most steppers for All Muscles (`group` nil) or one group.
private struct SetTargetEditor: View {
    @AppStorage(WeeklySetTarget.lowKey) private var targetLow = WeeklySetTarget.defaultLow
    @AppStorage(WeeklySetTarget.highKey) private var targetHigh = WeeklySetTarget.defaultHigh
    @AppStorage(WeeklySetTarget.groupsKey) private var storedGroups = ""
    let group: String?

    private var allRange: ClosedRange<Int> { targetLow...max(targetHigh, targetLow + 1) }
    private var groups: [String: ClosedRange<Int>] { WeeklySetTarget.decode(storedGroups) }
    private var range: ClosedRange<Int> { group.flatMap { groups[$0] } ?? allRange }

    /// All Muscles sets every group, as its row promises; a group matching All Muscles drops its own range.
    private func store(_ new: ClosedRange<Int>) {
        if let group {
            var updated = groups
            updated[group] = new == allRange ? nil : new
            storedGroups = WeeklySetTarget.encode(updated)
        } else {
            targetLow = new.lowerBound
            targetHigh = new.upperBound
            storedGroups = ""
        }
    }

    var body: some View {
        List {
            Section {
                Stepper(value: Binding(get: { range.lowerBound }, set: { store($0...max(range.upperBound, $0 + 1)) }),
                        in: 1...59) {
                    LabeledContent("At Least", value: "\(range.lowerBound) sets")
                }
                Stepper(value: Binding(get: { range.upperBound }, set: { store(min(range.lowerBound, $0 - 1)...$0) }),
                        in: 2...60) {
                    LabeledContent("At Most", value: "\(range.upperBound) sets")
                }
            } footer: {
                Text(group == nil
                     ? (groups.isEmpty ? "Muscle Focus shades this range for every muscle." : "Changing this gives every muscle this range, replacing their own.")
                     : "Muscle Focus shades this range in the \(HomeWeekSummary.displayName(group ?? "")) row.")
            }
            if let group, groups[group] != nil {
                Section {
                    Button("Use All Muscles Range") {
                        var updated = groups
                        updated[group] = nil
                        storedGroups = WeeklySetTarget.encode(updated)
                    }
                }
            }
        }
        .navigationTitle(group.map(HomeWeekSummary.displayName) ?? "All Muscles")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Edit Body: which measurements Body lists under its weight chart (build 117).
struct BodyRowsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeBodyRows.key) private var storedRows: String?

    var body: some View {
        let rows = HomeBodyRows.decode(storedRows)
        NavigationStack {
            List {
                Section {
                    ForEach(HomeBodyRows.choices) { kind in
                        let isShown = rows.contains(kind)
                        Button {
                            storedRows = HomeBodyRows.encode(isShown ? rows.filter { $0 != kind } : rows + [kind])
                        } label: {
                            HStack {
                                Text(kind.title)
                                    .foregroundStyle(LiteweightTheme.primaryText)
                                Spacer()
                                if isShown {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(LiteweightTheme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(isShown ? .isSelected : [])
                    }
                } header: {
                    Text("Listed Under Weight")
                } footer: {
                    Text("Body weight stays at the top with its chart.")
                }
            }
            .navigationTitle("Body")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
