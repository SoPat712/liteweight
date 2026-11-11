//
//  HistoryView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 22.06.19.
//

import SwiftUI
import CoreData
import WorkoutDataKit
import TipKit

struct HistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @Environment(\.sceneStateReference) private var sceneState
    @Environment(\.managedObjectContext) private var managedObjectContext
    @ObservedObject private var historyStore = TrainingHistoryStore.shared

    @State private var activityItems: [Any]?
    /// Deleted rows hide at once and are removed for good when the Undo toast expires.
    @State private var pendingDeletions: Set<NSManagedObjectID> = []
    @State private var showingRepeatBlocked = false
    @State private var showingShareUnavailable = false
    @State private var persistenceError: String?
    @State private var searchText = ""
    @AppStorage(LiteweightTips.generationKey) private var tipGeneration = 0
    @State private var showsSwipeTip = false
    @Namespace private var workoutDetailNamespace

    var body: some View {
        navigationContent
        .animation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion), value: pendingDeletions)
        .sheet(isPresented: $showingRepeatBlocked) {
            LiteweightStatusSheet(
                headerTitle: "Workout in progress",
                title: "Finish your current workout first",
                message: "Your active workout is safely stored on this iPhone. Finish or discard it before repeating another session.",
                systemImage: "figure.strengthtraining.traditional",
                tint: LiteweightTheme.warning,
                actionTitle: "Got It"
            )
            .modifier(HistoryStatusPresentation())
        }
        .sheet(isPresented: $showingShareUnavailable) {
            LiteweightStatusSheet(
                headerTitle: "Share workout",
                title: "Nothing to share yet",
                message: "This workout does not contain a completed set log. Add or complete a set before sharing it.",
                systemImage: "square.and.arrow.up",
                tint: LiteweightTheme.accent,
                actionTitle: "Got It"
            )
            .modifier(HistoryStatusPresentation())
        }
        .liteweightActivitySheet(activityItems: $activityItems)
        .alert("Workout Not Saved", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var navigationContent: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { historyList }
        } else {
            NavigationView { historyList }
                .navigationViewStyle(.stack)
        }
    }

    private var historyList: some View {
        List {
            if let error = historyStore.error {
                Section {
                    Button("Retry Loading History") { historyStore.refresh() }
                } footer: { Text(error) }
            } else if historyStore.isLoading && historyStore.snapshot.sessions.isEmpty {
                Section { ProgressView("Loading History…") }
            } else {
                workoutHistoryContent
            }
        }
        .listStyle(.insetGrouped)
        .liteweightTracksTip(HistorySwipeTip(generation: tipGeneration), isShowing: $showsSwipeTip)
        .modifier(HistoryScrollEdge())
        .modifier(HistoryScrollClearance())
        .navigationTitle("History")
        .modifier(HistoryTitleDisplayMode())
        .titleRowSearchable(text: $searchText, prompt: "Search Workouts")
        .task { historyStore.observe(in: managedObjectContext) }
    }

    private var searchTerms: [String] {
        searchText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private var matchingSessions: [TrainingSessionSnapshot] {
        let terms = searchTerms
        return visibleSessions.filter { session in
            // Search only immutable history and the in-memory catalog, never managed objects.
            let titles = [session.displayTitle] + session.exercises.compactMap {
                $0.uuid.flatMap { exerciseStore.exercisesByUUID[$0]?.title }
            }
            return terms.allSatisfy { term in
                titles.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil }
            }
        }.sorted { $0.date > $1.date }
    }

    private var visibleSessions: [TrainingSessionSnapshot] {
        guard !pendingDeletions.isEmpty else { return historyStore.snapshot.sessions }
        return historyStore.snapshot.sessions.filter { !pendingDeletions.contains($0.id) }
    }

    @ViewBuilder
    private var workoutHistoryContent: some View {
        let completed = visibleSessions
        let records = historyStore.snapshot.recordSetIDs
        if searchText.isEmpty {
            // The tab's voice: last week's count and how long since it was matched (build 121).
            LiteweightVoiceSection(text: TabVoiceLine.text(
                TabVoiceLine.history(sessionDates: completed.map(\.date), now: Date())))
        }
        if !searchText.isEmpty {
            let matches = matchingSessions
            if matches.isEmpty {
                historyEmptyRow(title: "No Workouts Found", message: "Try an exercise name, like bench.")
            } else {
                ForEach(matches) { session in
                    workoutHistoryLink(session, recordSetIDs: records)
                }
            }
        } else if completed.isEmpty {
            Section("Workouts") {
                historyEmptyRow(title: "No Workouts Yet", message: "Finished workouts, volume, effort, and personal records appear here.")
            }
        } else {
            let weeks = HistoryWorkoutWeek.group(completed)
            // Swipes only make sense once there's more than one workout to act on.
            if completed.count >= 2, showsSwipeTip {
                LiteweightTipSection(tip: HistorySwipeTip(generation: tipGeneration))
            }
            ForEach(weeks) { week in
                Section {
                    ForEach(week.workouts) { session in
                        workoutHistoryLink(session, recordSetIDs: records)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(LiteweightFormat.weekTitle(start: week.id))
                        Spacer(minLength: 8)
                        Text("\(week.workouts.count) workout\(week.workouts.count == 1 ? "" : "s")")
                            .font(.liteweightMetric(.caption, weight: .semibold))
                    }
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .lineLimit(1)
                    .textCase(nil)
                } footer: {
                    if week.id == weeks.last?.id {
                        Text("\(completed.count) completed workout\(completed.count == 1 ? "" : "s").")
                    }
                }
            }
        }
    }

    private func historyEmptyRow(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).foregroundStyle(LiteweightTheme.primaryText)
            Text(message).font(.subheadline).foregroundStyle(LiteweightTheme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }

    private func workoutHistoryLink(_ session: TrainingSessionSnapshot, recordSetIDs: Set<NSManagedObjectID>) -> some View {
        let workout = managedObjectContext.object(with: session.id) as! Workout
        return NavigationLink {
            if #available(iOS 18.0, *), !reduceMotion {
                WorkoutDetailView(workout: workout)
                    .environmentObject(settingsStore)
                    .navigationTransition(.zoom(sourceID: workout.objectID, in: workoutDetailNamespace))
            } else {
                WorkoutDetailView(workout: workout)
                    .environmentObject(settingsStore)
            }
        } label: {
            if #available(iOS 18.0, *), !reduceMotion {
                WorkoutHistoryRow(session: session, workout: workout, recordSetIDs: recordSetIDs)
                    .matchedTransitionSource(id: workout.objectID, in: workoutDetailNamespace)
            } else {
                WorkoutHistoryRow(session: session, workout: workout, recordSetIDs: recordSetIDs)
            }
        }
        .swipeActions(edge: .leading) {
            Button { repeatWorkout(workout, blank: false) } label: { Label("Repeat", systemImage: "arrow.clockwise") }
                .tint(LiteweightTheme.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(session, workout: workout) } label: { Label("Delete", systemImage: "trash.fill") }
            Button {
                share(workout)
            } label: { Label("Share", systemImage: "square.and.arrow.up") }
            .tint(LiteweightTheme.secondaryText)
        }
        .contextMenu {
            Button { repeatWorkout(workout, blank: false) } label: { Label("Repeat Workout", systemImage: "arrow.clockwise") }
            Button { repeatWorkout(workout, blank: true) } label: { Label("Repeat with Blank Sets", systemImage: "doc") }
            Button { share(workout) } label: { Label("Share Workout", systemImage: "square.and.arrow.up") }
            Divider()
            Button(role: .destructive) { delete(session, workout: workout) } label: { Label("Delete Workout", systemImage: "trash") }
        } preview: {
            HistoryWorkoutPreview(session: session)
                .environmentObject(settingsStore)
                .environmentObject(exerciseStore)
        }
    }

    /// Hides the row now and deletes when the toast expires, so Undo needs no restore.
    /// Deleting also removes liteweight's matching Apple Health workout, which is why it waits.
    private func delete(_ session: TrainingSessionSnapshot, workout: Workout) {
        HistorySwipeTip(generation: tipGeneration).invalidate(reason: .actionPerformed)
        let id = session.id
        pendingDeletions.insert(id)
        LiteweightToastCenter.shared.show(LiteweightToast(
            title: "Workout Deleted",
            subtitle: session.displayTitle,
            systemImage: "trash.fill",
            style: .info,
            duration: 5,
            actionTitle: "Undo",
            action: { pendingDeletions.remove(id) },
            onExpire: {
                // The id stays hidden until the background snapshot drops the deleted row.
                do {
                    if !workout.isDeleted { try workout.delete() }
                } catch {
                    pendingDeletions.remove(id)
                    persistenceError = "The workout was not deleted. \(error.localizedDescription)"
                }
            }
        ))
    }

    private func share(_ workout: Workout) {
        guard let log = workout.logText(
            in: exerciseStore.exercises,
            weightUnit: settingsStore.weightUnit
        ) else {
            showingShareUnavailable = true
            return
        }
        activityItems = [log]
    }

    private func repeatWorkout(_ workout: Workout, blank: Bool) {
        HistorySwipeTip(generation: tipGeneration).invalidate(reason: .actionPerformed)
        do {
            let didStart: Bool
            if blank {
                didStart = try WorkoutDetailView.repeatWorkoutBlank(
                    workout: workout,
                    settingsStore: settingsStore,
                    sceneState: sceneState
                )
            } else {
                didStart = try WorkoutDetailView.repeatWorkout(
                    workout: workout,
                    settingsStore: settingsStore,
                    sceneState: sceneState
                )
            }

            if !didStart { showingRepeatBlocked = true }
        } catch {
            persistenceError = "The workout was not started. \(error.localizedDescription)"
        }
    }

}

private struct HistoryWorkoutWeek: Identifiable {
    let id: Date
    let workouts: [TrainingSessionSnapshot]

    static func group(_ workouts: [TrainingSessionSnapshot]) -> [Self] {
        let grouped = Dictionary(grouping: workouts) { workout in
            Calendar.current.dateInterval(of: .weekOfYear, for: workout.date)?.start ?? .distantPast
        }
        return grouped.keys.sorted(by: >).map {
            Self(id: $0, workouts: (grouped[$0] ?? []).sorted { $0.date > $1.date })
        }
    }
}

private struct WorkoutHistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    let session: TrainingSessionSnapshot
    @ObservedObject var workout: Workout
    let recordSetIDs: Set<NSManagedObjectID>

    private var recordCount: Int {
        let exercises = workout.workoutExercises?.array as? [WorkoutExercise] ?? []
        return exercises.reduce(0) { total, exercise in
            total + (exercise.workoutSets?.array as? [WorkoutSet] ?? []).filter {
                $0.isCompleted && recordSetIDs.contains($0.objectID)
            }.count
        }
    }

    private var volumeNumber: String {
        WeightUnit.convert(weight: session.volume, from: .metric, to: settingsStore.weightUnit)
            .formatted(.number.precision(.fractionLength(0)))
    }

    private var exerciseSummary: String {
        let titles = session.exercises.enumerated().sorted {
            if $0.element.setCount == $1.element.setCount { return $0.offset < $1.offset }
            return $0.element.setCount > $1.element.setCount
        }.map { item in
            item.element.uuid.flatMap { exerciseStore.exercisesByUUID[$0]?.title } ?? "Unknown Exercise"
        }
        let leading = titles.prefix(2).joined(separator: ", ")
        return titles.count > 2 ? leading + " +\(titles.count - 2)" : leading
    }

    private var metadata: Text {
        let duration = metricNumber(LiteweightFormat.duration(session.duration))
        return Text(LiteweightFormat.listDate(session.date)) + Text(" · ") + duration
            + Text(" · ") + metricNumber("\(session.setCount)") + Text(" sets · ")
            + metricNumber(volumeNumber) + Text(" \(settingsStore.weightUnit.unit.symbol)")
    }

    private func metricNumber(_ value: String) -> Text {
        Text(value)
            .font(.liteweightMetric(.subheadline, weight: .semibold))
            .foregroundColor(LiteweightTheme.primaryText)
    }

    var body: some View {
        let records = recordCount
        let groups = session.muscleGroups(in: exerciseStore.exercisesByUUID)
        HStack(alignment: .top, spacing: 12) {
            // The figure leads the row in place of the tile: it carries the same colors and
            // shows every muscle. Accessibility sizes keep the tile and the named chips.
            if !groups.isEmpty, !dynamicTypeSize.isAccessibilitySize {
                LiteweightMuscleFigure(exerciseIDs: session.exercises.compactMap(\.uuid))
            } else {
                LiteweightMuscleTile(group: groups.first)
                    .padding(.top, 2)
            }
            details(records: records, groups: groups)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(groups.prefix(3).map { HomeWeekSummary.displayName($0) }.joined(separator: ", "))
    }

    private func details(records: Int, groups: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(workout.displayTitle(in: exerciseStore.exercises))
                    .font(.headline)
                    .foregroundStyle(LiteweightTheme.primaryText)
                    .lineLimit(2)
                if records > 0 {
                    Image(systemName: "trophy.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LiteweightTheme.metricRecord)
                        .accessibilityLabel("\(records) personal record\(records == 1 ? "" : "s")")
                }
            }
            metadata
                .font(.subheadline)
                .foregroundStyle(LiteweightTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if groups.isEmpty {
                Text(exerciseSummary)
                    .font(.footnote)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .lineLimit(1)
            } else {
                // Colored chips name the groups the figure lights, at every size (build 121);
                // at accessibility sizes they stand in for the figure. The row's value already
                // speaks the groups, so VoiceOver skips the chips.
                LiteweightChipFlow(spacing: 5) {
                    ForEach(groups.prefix(3), id: \.self) { LiteweightMuscleChip(group: $0) }
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TrainingSessionSnapshot {
    /// The colored muscle groups this session trained, most sets first.
    func muscleGroups(in catalog: [UUID: Exercise]) -> [String] {
        var sets: [String: Int] = [:]
        var order: [String] = []
        for item in exercises {
            guard let group = item.uuid.flatMap({ catalog[$0]?.muscleGroup }),
                  LiteweightPalette.hasMuscleColor(group) else { continue }
            if sets[group] == nil { order.append(group) }
            sets[group, default: 0] += max(item.setCount, 1)
        }
        return order.enumerated()
            .sorted { (sets[$0.element] ?? 0, -$0.offset) > (sets[$1.element] ?? 0, -$1.offset) }
            .map(\.element)
    }
}

/// The long-press preview: what was done, so a workout can be picked to repeat
/// without opening it.
private struct HistoryWorkoutPreview: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    let session: TrainingSessionSnapshot

    var body: some View {
        let groups = session.muscleGroups(in: exerciseStore.exercisesByUUID)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LiteweightMuscleTile(group: groups.first, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundStyle(LiteweightTheme.primaryText)
                    Text(LiteweightFormat.listDate(session.date))
                        .font(.subheadline)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                }
            }
            LiteweightWorkoutMetricLine(
                duration: LiteweightFormat.duration(session.duration), sets: session.setCount,
                volume: WeightUnit.convert(weight: session.volume, from: .metric, to: settingsStore.weightUnit)
                    .formatted(.number.precision(.fractionLength(0))),
                unit: settingsStore.weightUnit.unit.symbol
            )
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(session.exercises.prefix(8).enumerated()), id: \.offset) { _, item in
                    let exercise = item.uuid.flatMap { exerciseStore.exercisesByUUID[$0] }
                    HStack(spacing: 8) {
                        Circle()
                            .fill(LiteweightTheme.muscle(exercise?.muscleGroup))
                            .frame(width: 8, height: 8)
                        Text(exercise?.title ?? "Unknown Exercise")
                            .font(.subheadline)
                            .foregroundStyle(LiteweightTheme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        (Text("\(item.setCount)").font(.liteweightMetric(.subheadline, weight: .semibold))
                         + Text(item.setCount == 1 ? " set" : " sets"))
                            .font(.subheadline)
                            .foregroundStyle(LiteweightTheme.secondaryText)
                    }
                }
                if session.exercises.count > 8 {
                    Text("+\(session.exercises.count - 8) more")
                        .font(.footnote)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(LiteweightTheme.surface)
    }
}

private struct HistoryScrollEdge: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // Translucent: rows soften under the pinned search instead of meeting a solid band.
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct HistoryTitleDisplayMode: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.toolbarTitleDisplayMode(.inlineLarge)
        } else {
            content.navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct HistoryScrollClearance: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentMargins(.bottom, LiteweightTheme.floatingWorkoutBottomClearance, for: .scrollContent)
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance).allowsHitTesting(false)
            }
        }
    }
}

private struct HistoryStatusPresentation: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.height(390), .medium]).presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

#if DEBUG
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView().mockEnvironment(weightUnit: .metric)
    }
}
#endif
