//
//  WorkoutRoutineView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 21.03.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import CoreData
import WorkoutDataKit

/// Preferences follow the saved-workout draft's save boundary. Cancelling or a
/// failed Core Data save must not publish a different global type/distance target.
final class RoutineSetTrackingDraft: ObservableObject {
    @Published private(set) var changes = SetTrackingPreferences()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func override(for exerciseID: UUID?) -> SetTrackingType? {
        guard let exerciseID else { return nil }
        return changes.overrides[exerciseID.uuidString]?.type
            ?? SetTrackingPreferences.override(for: exerciseID, defaults: defaults)
    }
    func distance(for setID: UUID?) -> Double? {
        guard let setID else { return nil }
        if let changed = changes.routineDistances[setID.uuidString] { return changed.meters > 0 ? changed.meters : nil }
        return SetTrackingPreferences.routineDistance(for: setID, defaults: defaults)
    }
    func setOverride(_ type: SetTrackingType, for exerciseID: UUID) {
        changes.overrides[exerciseID.uuidString] = .init(type: type, updatedAt: Date().timeIntervalSince1970)
    }
    func setDistance(_ meters: Double?, for setID: UUID) {
        let value = meters.map { $0.isFinite ? max($0, 0) : 0 } ?? 0
        changes.routineDistances[setID.uuidString] = .init(meters: value, updatedAt: Date().timeIntervalSince1970)
    }
    /// Capture effective types as well as explicit overrides: after copying empty
    /// targets there may be no measurements left from which to infer the type.
    func copyTracking(from source: WorkoutRoutine, to destination: WorkoutRoutine) {
        let sources = source.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
        let destinations = destination.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
        for (source, destination) in zip(sources, destinations) {
            if let id = destination.exerciseUuid {
                setOverride(source.trackingType(catalogExercise: source.exerciseUuid.flatMap {
                    ExerciseStore.shared.exercisesByUUID[$0]
                }, defaults: defaults), for: id)
            }
            let sourceSets = source.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
            let destinationSets = destination.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
            for (sourceSet, destinationSet) in zip(sourceSets, destinationSets) {
                if let id = destinationSet.uuid { setDistance(distance(for: sourceSet.uuid), for: id) }
            }
        }
    }
    func discard() { changes = SetTrackingPreferences() }

    /// Deleted draft rows must not leave new, unreachable distance preferences.
    func retainMetadata(for routine: WorkoutRoutine) {
        let exercises = routine.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
        let exerciseIDs = Set(exercises.compactMap { $0.exerciseUuid?.uuidString })
        let setIDs = Set(exercises.flatMap {
            ($0.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []).compactMap { $0.uuid?.uuidString }
        })
        changes.overrides = changes.overrides.filter { exerciseIDs.contains($0.key) }
        changes.routineDistances = changes.routineDistances.filter { setIDs.contains($0.key) }
    }
    func commit() {
        guard !changes.isEmpty else { return }
        let stored = SetTrackingPreferences.load(defaults: defaults)
        let merged = stored.merging(changes)
        merged.save(defaults: defaults)
        changes = SetTrackingPreferences()
        if merged != stored {
            NotificationCenter.default.post(name: SetTrackingPreferences.didChangeNotification, object: defaults)
        }
    }
}

/// A focused editor for one saved workout plan.
///
/// Editable values stay close to the exercise they describe in logger-style cards.
struct WorkoutRoutineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var exerciseStore: ExerciseStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.managedObjectContext) var managedObjectContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var workoutRoutine: WorkoutRoutine

    let isNew: Bool
    let autosavesChanges: Bool
    let onCancel: (() -> Void)?
    let onCommit: (() -> Void)?

    @StateObject private var trackingDraft: RoutineSetTrackingDraft
    @State private var showExerciseSelector = false
    @State private var workoutRoutineTitleInput: String?
    @State private var workoutRoutineCommentInput: String?
    @State private var routineExerciseToDelete: WorkoutRoutineExercise?
    @State private var selectionFeedback = 0
    @State private var deleteFeedback = 0

    init(
        workoutRoutine: WorkoutRoutine,
        isNew: Bool = false,
        autosavesChanges: Bool = true,
        trackingDraft: RoutineSetTrackingDraft = RoutineSetTrackingDraft(),
        onCancel: (() -> Void)? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self.workoutRoutine = workoutRoutine
        self.isNew = isNew
        self.autosavesChanges = autosavesChanges
        _trackingDraft = StateObject(wrappedValue: trackingDraft)
        self.onCancel = onCancel
        self.onCommit = onCommit
    }

    private var workoutRoutineTitle: Binding<String> {
        Binding(
            // A plan without a custom title still has a real fallback title
            // (Workout A, Workout B, …). Present that value as editable text instead
            // of making the field look accidentally empty.
            get: { workoutRoutineTitleInput ?? workoutRoutine.displayTitle },
            set: { workoutRoutineTitleInput = $0 }
        )
    }

    private var workoutRoutineComment: Binding<String> {
        Binding(
            get: { workoutRoutineCommentInput ?? workoutRoutine.comment ?? "" },
            set: { workoutRoutineCommentInput = $0 }
        )
    }

    private var workoutRoutineExercises: [WorkoutRoutineExercise] {
        workoutRoutine.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
    }

    private var exerciseSelectorSheet: some View {
        AddExercisesSheet(
            exercises: exerciseStore.shownExercises,
            recentExercises: AddExercisesSheet.loadRecentExercises(
                context: managedObjectContext,
                exercises: exerciseStore.shownExercises
            ),
            onAdd: { selection in
                for exercise in selection {
                    let routineExercise = WorkoutRoutineExercise.create(context: managedObjectContext)
                    routineExercise.workoutRoutine = workoutRoutine
                    routineExercise.exerciseUuid = exercise.uuid
                }
                recordDraftChange()
            }
        )
    }

    private func recordDraftChange() {
        managedObjectContext.processPendingChanges()
        if autosavesChanges {
            managedObjectContext.saveOrCrash()
            trackingDraft.commit()
        }
    }

    private func saveRoutineExerciseNote(_ text: String, for exercise: WorkoutRoutineExercise) -> Bool {
        guard !exercise.isDeleted else { return false }
        do {
            try managedObjectContext.persistMutation(save: {
                if autosavesChanges { try managedObjectContext.save() }
            }) {
                exercise.comment = text.isEmpty ? nil : text
            }
            if autosavesChanges { trackingDraft.commit() }
            return true
        } catch {
            return false // The note sheet keeps its draft visible for retry.
        }
    }

    private func saveRoutineFields() {
        if let input = workoutRoutineTitleInput {
            let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
            workoutRoutineTitleInput = title
            workoutRoutine.title = title.isEmpty ? nil : title
        }
        if let input = workoutRoutineCommentInput {
            let comment = input.trimmingCharacters(in: .whitespacesAndNewlines)
            workoutRoutineCommentInput = comment
            workoutRoutine.comment = comment.isEmpty ? nil : comment
        }
        recordDraftChange()
    }

    private func sets(for routineExercise: WorkoutRoutineExercise) -> [WorkoutRoutineSet] {
        routineExercise.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
    }

    private func addSet(to routineExercise: WorkoutRoutineExercise) {
        let previousSet = sets(for: routineExercise).last
        let routineSet = WorkoutRoutineSet.create(context: managedObjectContext)
        routineSet.workoutRoutineExercise = routineExercise
        let type = trackingDraft.override(for: routineExercise.exerciseUuid) ?? routineExercise.setTrackingType
        routineSet.durationValue = type.usesDuration ? (previousSet?.durationValue ?? 60) : nil
        routineSet.weightValue = type.usesWeight ? previousSet?.weightValue : nil
        routineSet.minRepetitionsValue = type.usesReps ? (previousSet?.minRepetitionsValue ?? 5) : nil
        routineSet.maxRepetitionsValue = type.usesReps ? (previousSet?.maxRepetitionsValue ?? 5) : nil
        if type.usesDistance, let setID = routineSet.uuid {
            trackingDraft.setDistance(trackingDraft.distance(for: previousSet?.uuid), for: setID)
        }
        recordDraftChange()
    }

    private func deleteSet(_ routineSet: WorkoutRoutineSet) {
        routineSet.workoutRoutineExercise?.removeFromWorkoutRoutineSets(routineSet)
        managedObjectContext.delete(routineSet)
        recordDraftChange()
        deleteFeedback += 1
    }

    private func moveSet(in routineExercise: WorkoutRoutineExercise, from source: Int, to destination: Int) {
        let currentSets = sets(for: routineExercise)
        guard source != destination,
              currentSets.indices.contains(source),
              currentSets.indices.contains(destination) else { return }

        var reordered = currentSets
        let routineSet = reordered.remove(at: source)
        reordered.insert(routineSet, at: destination)
        routineExercise.workoutRoutineSets = NSOrderedSet(array: reordered)
        recordDraftChange()
        selectionFeedback += 1
    }

    private func deleteExercise(_ routineExercise: WorkoutRoutineExercise) {
        routineExercise.workoutRoutine?.removeFromWorkoutRoutineExercises(routineExercise)
        managedObjectContext.delete(routineExercise)
        recordDraftChange()
        deleteFeedback += 1
    }

    private func moveExercise(from source: Int, to destination: Int) {
        guard source != destination,
              workoutRoutineExercises.indices.contains(source),
              workoutRoutineExercises.indices.contains(destination) else { return }

        var reordered = workoutRoutineExercises
        let routineExercise = reordered.remove(at: source)
        reordered.insert(routineExercise, at: destination)
        workoutRoutine.workoutRoutineExercises = NSOrderedSet(array: reordered)
        recordDraftChange()
        selectionFeedback += 1
    }

    private var workoutDetailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: workoutRoutineTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(LiteweightTheme.primaryText)
                .textInputAutocapitalization(.words)
                .onSubmit(saveRoutineFields)

            TextField("Add notes…", text: workoutRoutineComment, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(LiteweightTheme.secondaryText)
                .lineLimit(1...5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous)
                .fill(LiteweightTheme.surface)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                workoutDetailsCard

                if workoutRoutineExercises.isEmpty {
                    ContentUnavailableView {
                        Label("No Exercises", systemImage: "dumbbell")
                    } description: {
                        Text("Add an exercise to start setting targets and rest times.")
                    } actions: {
                        Button("Add Exercise") { showExerciseSelector = true }
                            .liteweightProminentGlassButtonStyle()
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(Array(workoutRoutineExercises.enumerated()), id: \.element.id) { index, routineExercise in
                        WorkoutRoutineExerciseSection(
                            routineExercise: routineExercise,
                            exercise: routineExercise.exercise(in: exerciseStore.exercises),
                            index: index,
                            exerciseCount: workoutRoutineExercises.count,
                            onSave: recordDraftChange,
                            onSaveNote: { saveRoutineExerciseNote($0, for: routineExercise) },
                            onMoveUp: { moveExercise(from: index, to: index - 1) },
                            onMoveDown: { moveExercise(from: index, to: index + 1) },
                            onDelete: { routineExerciseToDelete = routineExercise },
                            onAddSet: { addSet(to: routineExercise) },
                            onDeleteSet: { deleteSet($0) },
                            onMoveSet: { source, destination in
                                moveSet(in: routineExercise, from: source, to: destination)
                            }
                        )
                    }

                    Button {
                        showExerciseSelector = true
                    } label: {
                        Label("Add Exercises", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .liteweightProminentGlassButtonStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
        }
        .background(LiteweightTheme.background)
        .environmentObject(trackingDraft)
        .sensoryFeedback(.selection, trigger: selectionFeedback) { _, _ in settingsStore.workoutHaptics }
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteFeedback) { _, _ in settingsStore.workoutHaptics }
        .animation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion), value: workoutRoutineExercises.map(\.objectID))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isNew ? "New Workout" : "Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancelEditor)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Update", action: commitEditor)
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showExerciseSelector) {
            exerciseSelectorSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Remove exercise from workout?",
            isPresented: Binding(
                get: { routineExerciseToDelete != nil },
                set: { if !$0 { routineExerciseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                guard let routineExercise = routineExerciseToDelete else { return }
                routineExerciseToDelete = nil
                deleteExercise(routineExercise)
            }
            Button("Cancel", role: .cancel) {
                routineExerciseToDelete = nil
            }
        } message: {
            Text("Its target sets, rest timer, and workout notes will be removed. Completed workout history is not affected.")
        }
    }

    private func cancelEditor() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func commitEditor() {
        saveRoutineFields()
        if let onCommit {
            onCommit()
        } else {
            managedObjectContext.saveOrCrash()
            trackingDraft.retainMetadata(for: workoutRoutine)
            trackingDraft.commit()
            dismiss()
        }

    }

}

private struct WorkoutRoutineExerciseSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject private var settingsStore: SettingsStore

    @EnvironmentObject private var trackingDraft: RoutineSetTrackingDraft
    @ObservedObject var routineExercise: WorkoutRoutineExercise
    @State private var showingRestTimerEditor = false
    @State private var showingNoteEditor = false
    @State private var selectionFeedback = 0
    @State private var historySets: [WorkoutSet] = []
    let exercise: Exercise?
    let index: Int
    let exerciseCount: Int
    let onSave: () -> Void
    let onSaveNote: (String) -> Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onAddSet: () -> Void
    let onDeleteSet: (WorkoutRoutineSet) -> Void
    let onMoveSet: (Int, Int) -> Void

    // Observe the relationship's owner instead of retaining a parent-render snapshot.
    private var sets: [WorkoutRoutineSet] {
        routineExercise.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
    }

    private func loadHistory() {
        let request = WorkoutExercise.historyFetchRequest(of: routineExercise.exerciseUuid)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            request.predicate ?? NSPredicate(value: true),
            NSPredicate(format: "%K != nil", #keyPath(WorkoutExercise.workout.end))
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutExercise.workout?.end, ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = ["workoutSets"]
        let previousExercise = (try? managedObjectContext.fetch(request))?.first
        historySets = previousExercise?.workoutSets?.array as? [WorkoutSet] ?? []
    }

    private func latestHistorySet(at index: Int) -> WorkoutSet? {
        let currentSets = sets
        guard currentSets.indices.contains(index) else { return nil }
        // Warm-up insertion must not shift the working sets' Previous values.
        let isWarmup = currentSets[index].tagValue == .warmUp
        let matching = historySets.filter { ($0.tagValue == .warmUp) == isWarmup }
        let ordinal = currentSets.prefix(index).filter { ($0.tagValue == .warmUp) == isWarmup }.count
        return matching.indices.contains(ordinal) ? matching[ordinal] : matching.last
    }

    private var restTimerTitle: String {
        let duration = routineExercise.restTimerDurationValue ?? workoutDefaultRestTimerDuration
        let formatted = restTimerDurationFormatter.string(from: duration) ?? "0:00"
        let time = formatted.count == 5 && formatted.hasPrefix("0") ? String(formatted.dropFirst()) : formatted
        return "Rest \(time)"
    }

    @AppStorage(SetTrackingPreferences.storageKey) private var trackingPreferencesData: Data?
    private var trackingType: SetTrackingType { trackingDraft.override(for: routineExercise.exerciseUuid) ?? routineExercise.setTrackingType }

    private var workoutDefaultRestTimerDuration: TimeInterval {
        switch exercise?.type {
        case .barbell: return settingsStore.defaultRestTimeBarbellBased
        case .dumbbell: return settingsStore.defaultRestTimeDumbbellBased
        default: return settingsStore.defaultRestTime
        }
    }

    private func setTrackingType(_ type: SetTrackingType) {
        guard type != trackingType, let exerciseID = routineExercise.exerciseUuid else { return }
        for set in sets {
            set.durationValue = type.usesDuration ? (set.durationValue ?? 60) : nil
            if !type.usesWeight { set.weightValue = nil }
            if type.usesReps {
                set.minRepetitionsValue = set.minRepetitionsValue ?? 5
                set.maxRepetitionsValue = set.maxRepetitionsValue ?? 5
            } else {
                set.minRepetitionsValue = nil
                set.maxRepetitionsValue = nil
            }
            if !type.usesDistance, let setID = set.uuid {
                trackingDraft.setDistance(nil, for: setID)
            }
        }
        trackingDraft.setOverride(type, for: exerciseID)
        onSave()
        selectionFeedback += 1
    }

    private var usesAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private var exerciseHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            if let exercise {
                ExerciseDiagramThumbnail(exercise: exercise, size: 42)
                    .frame(width: LiteweightTheme.iconButtonSize, height: LiteweightTheme.controlHeight)
            } else {
                Circle()
                    .fill(LiteweightTheme.tertiaryFill)
                    .frame(width: LiteweightTheme.iconButtonSize, height: LiteweightTheme.controlHeight)
                    .overlay(Image(systemName: "dumbbell.fill").foregroundStyle(LiteweightTheme.secondaryText))
            }

            VStack(alignment: .leading, spacing: 0) {
                if let exercise {
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                    } label: {
                        Text(exercise.title)
                            .font(.headline)
                            .foregroundStyle(LiteweightTheme.primaryText)
                            .lineLimit(usesAccessibilityLayout ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Unknown Exercise")
                        .font(.headline)
                        .foregroundStyle(LiteweightTheme.primaryText)
                        .lineLimit(usesAccessibilityLayout ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
                exerciseMetadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("Edit Workout Plan Note", systemImage: "list.bullet") { showingNoteEditor = true }
                Picker("Set Type", selection: Binding(get: { trackingType }, set: setTrackingType)) {
                    ForEach(SetTrackingType.allCases) { type in Text(type.title).tag(type) }
                }
                Button("Rest Timer", systemImage: "timer") { showingRestTimerEditor = true }
                Divider()
                if index > 0 {
                    Button("Move Up", systemImage: "arrow.up", action: onMoveUp)
                }
                if index < exerciseCount - 1 {
                    Button("Move Down", systemImage: "arrow.down", action: onMoveDown)
                }
                Section {
                    Button("Remove Exercise", systemImage: "trash", role: .destructive, action: onDelete)
                }
            } label: {
                Label("Exercise Actions", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(width: LiteweightTheme.iconButtonSize, height: LiteweightTheme.controlHeight)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(exercise?.title ?? "exercise")")
        }
    }

    private var exerciseMetadata: some View {
        let layout = usesAccessibilityLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
        let equipment = exercise?.equipment.map(\.equipmentTitle).joined(separator: ", ") ?? ""
        let group = exercise?.muscleGroup
        let lineTint: Color? = LiteweightPalette.hasMuscleColor(group) ? LiteweightTheme.muscleText(group) : nil
        return layout {
            if !equipment.isEmpty {
                Text(equipment + (usesAccessibilityLayout ? "" : " ·"))
                    .font(.subheadline)
                    .foregroundStyle(lineTint ?? LiteweightTheme.secondaryText)
                    .lineLimit(usesAccessibilityLayout ? 2 : 1)
            }
            Button {
                showingRestTimerEditor = true
            } label: {
                Text(restTimerTitle)
                    .font(.liteweightMetric(.subheadline, weight: .semibold))
                    .foregroundStyle(lineTint ?? LiteweightTheme.metricTime)
                    .lineLimit(usesAccessibilityLayout ? nil : 1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: !usesAccessibilityLayout, vertical: true)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .frame(minHeight: 24)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: restTimerTitle)
            .accessibilityLabel("Exercise rest length")
            .accessibilityValue(restTimerTitle)
            .accessibilityHint("Opens the rest duration picker")
        }
    }

    @ViewBuilder
    private var workoutPlanNote: some View {
        if let comment = routineExercise.comment,
           !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button { showingNoteEditor = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "list.bullet")
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    (Text("Workout plan: ").fontWeight(.semibold) + Text(comment))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
                .foregroundStyle(LiteweightTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: LiteweightTheme.controlHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, LiteweightTheme.iconButtonSize + 10)
            .accessibilityHint("Shown whenever you start this saved workout")
        }
    }

    @ViewBuilder
    private var setTableHeader: some View {
        if !usesAccessibilityLayout {
            HStack(spacing: InlineWorkoutSetLayout.spacing) {
                Text("SET")
                    .frame(width: InlineWorkoutSetLayout.setWidth)
                Text("PREVIOUS")
                    .frame(width: InlineWorkoutSetLayout.previousWidth, alignment: .center)
                ForEach(trackingType.columns) { column in
                    Text(trackingType.header(for: column, weightUnit: settingsStore.weightUnit.unit.symbol,
                                             distanceUnit: WorkoutSet.distanceUnit(settingsStore.weightUnit)))
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(LiteweightTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
            .padding(.bottom, InlineWorkoutSetLayout.spacing)
            .accessibilityHidden(true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            exerciseHeader
            workoutPlanNote
            setTableHeader

            ForEach(Array(sets.enumerated()), id: \.element.id) { setIndex, routineSet in
                WorkoutRoutineSetRow(
                    routineSet: routineSet,
                    index: setIndex,
                    setCount: sets.count,
                    trackingType: trackingType,
                    previousSet: latestHistorySet(at: setIndex),
                    onSave: onSave,
                    onMoveUp: { onMoveSet(setIndex, setIndex - 1) },
                    onMoveDown: { onMoveSet(setIndex, setIndex + 1) },
                    onDelete: { onDeleteSet(routineSet) }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }

            if sets.isEmpty {
                Text("No target sets yet.")
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onAddSet) {
                Label("Add Set", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .liteweightGlassButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 12)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous)
                .fill(LiteweightTheme.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous))
        .animation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion), value: sets.map(\.objectID))
        .sensoryFeedback(.selection, trigger: selectionFeedback) { _, _ in settingsStore.workoutHaptics }
        .task(id: routineExercise.exerciseUuid) { loadHistory() }
        .onDisappear(perform: onSave)
        .sheet(isPresented: $showingNoteEditor) {
            ExerciseNoteEditorSheet(
                title: "Workout Plan Note",
                subtitle: "Shown whenever you start from this saved workout.",
                text: routineExercise.comment ?? ""
            ) { text in
                onSaveNote(text)
            }
        }
        .sheet(isPresented: $showingRestTimerEditor) {
            RestTimerConfigurationSheet(
                title: "Rest Timer",
                subtitle: "Recovery after each completed set",
                initialDuration: routineExercise.restTimerDurationValue ?? workoutDefaultRestTimerDuration,
                secondaryActionTitle: "Use Workout Default · \(restTimerDurationFormatter.string(from: workoutDefaultRestTimerDuration) ?? "0:00")",
                onSecondaryAction: {
                    routineExercise.restTimerDurationValue = nil
                    onSave()
                },
                onApply: { duration in
                    routineExercise.restTimerDurationValue = duration
                    onSave()
                }
            )
        }
    }
}

private struct WorkoutRoutineSetRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore

    @EnvironmentObject private var trackingDraft: RoutineSetTrackingDraft
    @ObservedObject var routineSet: WorkoutRoutineSet
    @ScaledMetric(relativeTo: .footnote) private var previousFontSize: CGFloat = 13
    @State private var distanceInput: String?
    @AppStorage(SetTrackingPreferences.storageKey) private var trackingPreferencesData: Data?
    @State private var weightInput: String?
    @State private var repetitionsInput: String?
    @State private var showingDurationPicker = false
    @State private var showingPlateCalculator = false
    @State private var selectionFeedback = 0
    @FocusState private var focusedField: EntryField?
    let index: Int
    let setCount: Int
    let trackingType: SetTrackingType
    let previousSet: WorkoutSet?
    let onSave: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    private enum EntryField: Hashable {
        case weight
        case repetitions
        case distance
    }

    private var displayedWeightTitle: String {
        guard let weight = routineSet.weightValue else { return "" }
        let displayWeight = WeightUnit.convert(
            weight: weight,
            from: .metric,
            to: settingsStore.weightUnit
        )
        return settingsStore.weightUnit.numberFormatter.string(from: NSNumber(value: displayWeight)) ?? ""
    }

    private var weightText: Binding<String> {
        Binding(
            get: { weightInput ?? displayedWeightTitle },
            set: { input in
                let sanitized = sanitizedDecimalInput(input)
                guard input.isEmpty || !sanitized.isEmpty else { return }
                weightInput = sanitized
                updateWeight(from: sanitized)
            }
        )
    }

    private var repetitionsText: Binding<String> {
        Binding(
            get: { repetitionsInput ?? repetitionsTitle },
            set: { input in
                let sanitized = sanitizedRepetitionsInput(input)
                guard input.isEmpty || !sanitized.isEmpty else { return }
                repetitionsInput = sanitized
                updateRepetitions(from: sanitized)
            }
        )
    }

    private var plateCalculatorTarget: Double {
        max(
            routineSet.weightValue.map {
                WeightUnit.convert(weight: $0, from: .metric, to: settingsStore.weightUnit)
            } ?? 0,
            settingsStore.weightUnit.barbellWeight
        )
    }

    private func updateWeight(from input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            routineSet.weightValue = nil
            return
        }
        let parsed = settingsStore.weightUnit.numberFormatter.number(from: trimmed)?.doubleValue
            ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))
        guard let parsed = parsed else { return }
        routineSet.weightValue = WeightUnit.convert(
            weight: min(max(parsed, 0), maximumDisplayWeight),
            from: settingsStore.weightUnit,
            to: .metric
        )
    }

    private var maximumDisplayWeight: Double {
        WeightUnit.convert(
            weight: WorkoutSet.MAX_WEIGHT,
            from: .metric,
            to: settingsStore.weightUnit
        )
    }

    private func sanitizedDecimalInput(_ proposedValue: String) -> String {
        let formatter = settingsStore.weightUnit.numberFormatter
        let result = WeightUnit.sanitizedDecimalInput(
            proposedValue,
            maximumFractionDigits: settingsStore.weightUnit.maximumFractionDigits,
            decimalSeparator: formatter.decimalSeparator ?? Locale.current.decimalSeparator ?? ".",
            groupingSeparator: formatter.groupingSeparator ?? Locale.current.groupingSeparator ?? ","
        )

        if let value = formatter.number(from: result)?.doubleValue,
           value > maximumDisplayWeight {
            return formatter.string(from: NSNumber(value: maximumDisplayWeight)) ?? result
        }
        return result
    }

    private func sanitizedIntegerInput(_ proposedValue: String) -> String {
        let digits = proposedValue.compactMap(\.wholeNumberValue).map(String.init).joined()
        guard let value = Int(digits) else { return "" }
        return String(min(value, Int(WorkoutSet.MAX_REPETITIONS)))
    }

    private func sanitizedRepetitionsInput(_ proposedValue: String) -> String {
        let normalized = proposedValue.replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "−", with: "-")
        if normalized.contains("-") {
            return normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                .map { sanitizedIntegerInput(String($0)) }
                .joined(separator: "-")
        }
        let digits = sanitizedIntegerInput(normalized)
        // Preserve the editor's existing open-ended target representations, too.
        if normalized.hasPrefix("<") { return "<" + digits }
        if normalized.hasSuffix("+") { return digits + "+" }
        return digits
    }

    private var repetitionsTitle: String {
        if let min = routineSet.minRepetitionsValue, let max = routineSet.maxRepetitionsValue {
            return min == max ? "\(max)" : "\(min)-\(max)"
        }
        if let min = routineSet.minRepetitionsValue { return "\(min)+" }
        if let max = routineSet.maxRepetitionsValue { return "<\(max)" }
        return ""
    }

    private func updateRepetitions(from input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            routineSet.minRepetitionsValue = nil
            routineSet.maxRepetitionsValue = nil
            return
        }

        if value.contains("-") {
            let bounds = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard bounds.count == 2, let lower = Int16(bounds[0]), let upper = Int16(bounds[1]) else { return }
            routineSet.minRepetitionsValue = min(lower, upper)
            routineSet.maxRepetitionsValue = max(lower, upper)
        } else if value.hasPrefix("<") {
            guard let upper = Int16(value.dropFirst()) else { return }
            routineSet.minRepetitionsValue = nil
            routineSet.maxRepetitionsValue = upper
        } else if value.hasSuffix("+") {
            guard let lower = Int16(value.dropLast()) else { return }
            routineSet.minRepetitionsValue = lower
            routineSet.maxRepetitionsValue = nil
        } else {
            guard let parsed = Int(value) else { return }
            let repetitions = Int16(min(max(parsed, 0), Int(WorkoutSet.MAX_REPETITIONS)))
            routineSet.minRepetitionsValue = repetitions
            routineSet.maxRepetitionsValue = repetitions
        }
    }

    private var setLabel: String {
        switch routineSet.tagValue {
        case .warmUp: return "W"
        case .dropSet: return "D"
        case .failure: return "F"
        case nil: return "\(index + 1)"
        }
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var previousTitle: String {
        previousSet?.resultTitle(weightUnit: settingsStore.weightUnit) ?? "—"
    }

    private var compactPreviousTitle: String {
        let title = previousTitle.isEmpty ? "—" : previousTitle
        let font = UIFont.monospacedDigitSystemFont(ofSize: previousFontSize, weight: .semibold)
        guard (title as NSString).size(withAttributes: [.font: font]).width > InlineWorkoutSetLayout.previousWidth,
              !trackingType.usesDuration, title.contains(" × "), let previousSet else { return title }
        let weight = WeightUnit.convert(weight: previousSet.weightValue, from: .metric, to: settingsStore.weightUnit)
        let value = settingsStore.weightUnit.displayNumberFormatter.string(from: NSNumber(value: weight)) ?? "0"
        let sign = title.hasPrefix("+") ? "+" : (title.hasPrefix("−") ? "−" : "")
        return "\(sign)\(value) × \(previousSet.repetitionsValue)"
    }

    private var canFillFromPrevious: Bool {
        guard let previousSet else { return false }
        return (trackingType.usesWeight && previousSet.weight != nil)
            || (trackingType.usesDuration && previousSet.durationValue != nil)
            || (trackingType.usesDistance && previousSet.distanceValue != nil && routineSet.uuid != nil)
    }

    private func fillFromPrevious() {
        guard canFillFromPrevious, let previousSet else { return }
        focusedField = nil
        if trackingType.usesWeight, let weight = previousSet.weight?.doubleValue {
            routineSet.weightValue = weight
        }
        if trackingType.usesDuration, let duration = previousSet.durationValue {
            routineSet.durationValue = duration
        }
        if trackingType.usesDistance, let distance = previousSet.distanceValue, let setID = routineSet.uuid {
            trackingDraft.setDistance(distance, for: setID)
        }
        onSave()
        weightInput = nil
        repetitionsInput = nil
        distanceInput = nil
        selectionFeedback += 1
    }

    private var previousValue: some View {
        Text(usesAccessibilityLayout ? previousTitle : compactPreviousTitle)
            .font(.liteweightMetric(.footnote, weight: .semibold))
            .foregroundStyle(LiteweightTheme.secondaryText)
            .lineLimit(usesAccessibilityLayout ? nil : 3)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .frame(width: usesAccessibilityLayout ? nil : InlineWorkoutSetLayout.previousWidth, alignment: .center)
            .frame(minHeight: InlineWorkoutSetLayout.visualHeight)
            .background(LiteweightTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: LiteweightTheme.compactCornerRadius, style: .continuous))
            .accessibilityLabel("Previous: \(previousTitle)")
    }

    @ViewBuilder
    private var previousCell: some View {
        if canFillFromPrevious {
            Button(action: fillFromPrevious) {
                previousValue
                    .frame(minHeight: LiteweightTheme.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous: \(previousTitle)")
            .accessibilityHint("Fills this set from last time")
        } else {
            previousValue
        }
    }

    private var weightField: some View {
        setField(field: .weight, isFocused: focusedField == .weight) {
            TextField("—", text: weightText, onEditingChanged: { isEditing in
                if isEditing {
                    weightInput = displayedWeightTitle
                } else {
                    weightInput = nil
                    onSave()
                }
            })
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .weight)
            .accessibilityLabel("\(weightTitle) in \(settingsStore.weightUnit.unit.symbol)")
            .accessibilityValue(weightText.wrappedValue.isEmpty ? "Not set" : "\(weightText.wrappedValue) \(settingsStore.weightUnit.unit.symbol)")
        }
    }

    private var repetitionsField: some View {
        setField(field: .repetitions, isFocused: focusedField == .repetitions) {
            TextField("—", text: repetitionsText, onEditingChanged: { isEditing in
                if isEditing {
                    repetitionsInput = repetitionsTitle
                } else {
                    repetitionsInput = nil
                    onSave()
                }
            })
            .keyboardType(.numbersAndPunctuation)
            .focused($focusedField, equals: .repetitions)
            .accessibilityLabel("Target reps")
            .accessibilityValue(repetitionsText.wrappedValue.isEmpty ? "Not set" : "\(repetitionsText.wrappedValue) reps")
        }
    }

    private var durationControl: some View {
        Button {
            showingDurationPicker = true
        } label: {
            setField(isFocused: showingDurationPicker) {
                Text(SetTrackingType.durationText(routineSet.durationValue ?? 60))
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: routineSet.durationValue)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Duration")
        .accessibilityValue(SetTrackingType.durationText(routineSet.durationValue ?? 60))
    }

    private var distanceText: Binding<String> {
        Binding(get: {
            if let distanceInput { return distanceInput }
            guard let meters = trackingDraft.distance(for: routineSet.uuid) else { return "" }
            return settingsStore.weightUnit.numberFormatter.string(from: NSNumber(value: WorkoutSet.distanceDisplayValue(meters, weightUnit: settingsStore.weightUnit))) ?? ""
        }, set: { input in
            let sanitized = sanitizedDecimalInput(input)
            guard input.isEmpty || !sanitized.isEmpty else { return }
            distanceInput = sanitized
            let value = settingsStore.weightUnit.numberFormatter.number(from: sanitized)?.doubleValue ?? 0
            guard let setID = routineSet.uuid else { return }
            trackingDraft.setDistance(WorkoutSet.distanceMeters(value, weightUnit: settingsStore.weightUnit), for: setID)
            onSave()
        })
    }
    private var distanceField: some View {
        setField(field: .distance, isFocused: focusedField == .distance) {
            TextField("—", text: distanceText)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .distance)
                .accessibilityLabel("Distance in \(WorkoutSet.distanceUnit(settingsStore.weightUnit))")
        }
    }
    private var weightTitle: String {
        trackingType == .assistedBodyweight ? "Assistance" : (trackingType == .weightedBodyweight ? "Added Weight" : "Weight")
    }

    private var badgeColor: Color {
        routineSet.tagValue == .warmUp ? LiteweightTheme.metricSets : LiteweightTheme.secondaryText
    }

    private var badgeFill: Color {
        routineSet.tagValue == .warmUp ? LiteweightTheme.metricSetsContainer : LiteweightTheme.field
    }

    private var setTagBinding: Binding<WorkoutSetTag?> {
        Binding(
            get: { routineSet.tagValue },
            set: { newValue in
                guard routineSet.tagValue != newValue else { return }
                routineSet.tagValue = newValue
                onSave()
                selectionFeedback += 1
            }
        )
    }

    private func setTypeIcon(for tag: WorkoutSetTag) -> String {
        switch tag {
        case .warmUp: return "flame"
        case .dropSet: return "arrow.down.right"
        case .failure: return "bolt.fill"
        }
    }

    @ViewBuilder
    private var setTypeMenuItems: some View {
        Picker("Set Type", selection: setTagBinding) {
            Label("Normal Set", systemImage: "number").tag(WorkoutSetTag?.none)
            ForEach(WorkoutRoutineSet.supportedTags, id: \.self) { tag in
                Label(tag.title.capitalized, systemImage: setTypeIcon(for: tag))
                    .tag(WorkoutSetTag?.some(tag))
            }
        }
        if index > 0 {
            Button("Move Up", systemImage: "arrow.up", action: onMoveUp)
        }
        if index < setCount - 1 {
            Button("Move Down", systemImage: "arrow.down", action: onMoveDown)
        }
        Section {
            Button("Delete Set", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var setTypeMenu: some View {
        Menu { setTypeMenuItems } label: {
            if usesAccessibilityLayout {
                Text(routineSet.tagValue.map { "\($0.title.capitalized) · Set \(index + 1)" } ?? "Set \(index + 1)")
                    .font(.liteweightMetric(.headline))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .frame(minHeight: LiteweightTheme.controlHeight)
                    .background(badgeFill, in: Capsule())
            } else {
                Text(setLabel)
                    .font(.liteweightMetric(.title3))
                    .foregroundStyle(badgeColor)
                    .frame(width: InlineWorkoutSetLayout.visualHeight, height: InlineWorkoutSetLayout.visualHeight)
                    .background(badgeFill, in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(badgeColor, LiteweightTheme.surface)
                            .offset(x: 2, y: 2)
                            .accessibilityHidden(true)
                    }
                    .frame(width: LiteweightTheme.iconButtonSize, height: LiteweightTheme.controlHeight)
                    .contentShape(Rectangle())
                    .frame(width: InlineWorkoutSetLayout.setWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(index + 1) type")
        .accessibilityValue(routineSet.tagValue?.title ?? "Normal set")
        .accessibilityHint("Change set type or delete")
    }

    @ViewBuilder
    private func measurementField(_ column: SetTrackingType.Column) -> some View {
        switch column {
        case .weight: weightField
        case .reps: repetitionsField
        case .distance: distanceField
        case .duration: durationControl
        }
    }

    private func setField<Content: View>(
        field: EntryField? = nil,
        isFocused: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.liteweightMetric(.title3))
            .foregroundStyle(LiteweightTheme.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: InlineWorkoutSetLayout.visualHeight)
            .background(
                RoundedRectangle(cornerRadius: LiteweightTheme.compactCornerRadius, style: .continuous)
                    .fill(isFocused ? LiteweightTheme.accentSoft : LiteweightTheme.tertiaryFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiteweightTheme.compactCornerRadius, style: .continuous)
                            .strokeBorder(isFocused ? LiteweightTheme.accent : LiteweightTheme.outline, lineWidth: isFocused ? 2 : 0.5)
                    }
            )
            .frame(minHeight: LiteweightTheme.controlHeight)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                if let field { focusedField = field }
            }, including: field == nil ? .subviews : .all)
            .animation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion), value: isFocused)
    }

    private var regularCompactRow: some View {
        HStack(alignment: .center, spacing: InlineWorkoutSetLayout.spacing) {
            setTypeMenu
            previousCell
            ForEach(trackingType.columns) { column in
                measurementField(column)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: InlineWorkoutSetLayout.compactRowHeight)
    }

    private var accessibleCompactRow: some View {
        VStack(alignment: .leading, spacing: InlineWorkoutSetLayout.stackedSpacing) {
            setTypeMenu
            VStack(alignment: .leading, spacing: InlineWorkoutSetLayout.labelSpacing) {
                Text("PREVIOUS")
                    .font(.caption)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .accessibilityHidden(true)
                previousCell
            }
            ForEach(trackingType.columns) { column in
                VStack(alignment: .leading, spacing: InlineWorkoutSetLayout.labelSpacing) {
                    Text(trackingType.header(for: column, weightUnit: settingsStore.weightUnit.unit.symbol,
                                             distanceUnit: WorkoutSet.distanceUnit(settingsStore.weightUnit)))
                        .font(.caption)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                        .accessibilityHidden(true)
                    measurementField(column)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Group {
            if usesAccessibilityLayout {
                accessibleCompactRow
            } else {
                regularCompactRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(routineSet.tagValue.map { "Set \(index + 1), \($0.title)" } ?? "Set \(index + 1)")
        .onChange(of: trackingType) { _, _ in
            focusedField = nil
            weightInput = nil
            repetitionsInput = nil
            distanceInput = nil
        }
        .onChange(of: settingsStore.weightUnit) { _, _ in
            focusedField = nil
            weightInput = nil
            distanceInput = nil
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback) { _, _ in settingsStore.workoutHaptics }
        .contextMenu {
            setTypeMenuItems
        }
        .sheet(isPresented: $showingDurationPicker) {
            LiteweightDurationPickerSheet(
                initialDuration: routineSet.durationValue ?? 60
            ) { duration in
                routineSet.durationValue = duration
                onSave()
            }
        }
        .sheet(isPresented: $showingPlateCalculator) {
            LiteweightUtilitySheet(
                title: "Plate Calculator",
                subtitle: "",
                systemImage: "plusminus",
                showsDone: false,
                onClose: { showingPlateCalculator = false }
            ) {
                PlateCalculatorView(
                    unit: settingsStore.weightUnit,
                    initialTarget: plateCalculatorTarget,
                    exerciseKey: routineSet.workoutRoutineExercise?.exerciseUuid?.uuidString,
                    onClose: { showingPlateCalculator = false },
                    onApply: { value in
                        routineSet.weightValue = WeightUnit.convert(
                            weight: value,
                            from: settingsStore.weightUnit,
                            to: .metric
                        )
                        weightInput = nil
                        onSave()
                        showingPlateCalculator = false
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .toolbar {
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    if trackingType.usesWeight, focusedField == .weight {
                        Button("Plate Calculator", systemImage: "plusminus", action: openPlateCalculator)
                            .labelStyle(.iconOnly)
                            .accessibilityHint("Calculates the plates to load for this set")
                    }

                    Spacer()

                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func openPlateCalculator() {
        focusedField = nil
        DispatchQueue.main.async {
            showingPlateCalculator = true
        }
    }
}

#if DEBUG
struct WorkoutRoutineView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WorkoutRoutineView(workoutRoutine: MockWorkoutData.metric.workoutRoutine)
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
