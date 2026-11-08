//
//  WorkoutDetailView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 22.06.19.
//  Rebuilt as liteweight's editable workout summary.
//

import SwiftUI
import AVKit
import CoreData
import UIKit
import MuscleMap
import WorkoutDataKit

enum HistoryMutationPersistence {
    static func perform(
        context: NSManagedObjectContext,
        save: (() throws -> Void)? = nil,
        mutation: () throws -> Void,
        onSuccess: () -> Void = {}
    ) throws {
        try context.persistMutation(
            save: {
                if let save { try save() }
                else { try context.save() }
            },
            mutation: mutation
        )
        onSuccess()
    }
}

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @Environment(\.sceneStateReference) private var sceneState

    @ObservedObject var workout: Workout

    @State private var isEditing = false
    @State private var showingExerciseSelectorSheet = false
    @State private var activityItems: [Any]?
    @State private var workoutToDelete: Workout?
    @State private var workoutExerciseToDelete: WorkoutExercise?
    @State private var showingRepeatBlocked = false
    @State private var showingDetailsEditor = false
    @State private var showingMediaPreview = false
    @State private var healthSyncState = WorkoutHealthSyncState.idle
    @State private var showingShareUnavailable = false
    @State private var persistenceError: String?
    @State private var isNavigationTitleVisible = false
    /// Matches the logger's summary row (its muscle figure height).
    private let summaryHeight: CGFloat = 54

    private var workoutExercises: [WorkoutExercise] {
        workout.workoutExercises?.array as? [WorkoutExercise] ?? []
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                trackedWorkoutTitleHeader
                Text(workoutDateSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 16)

                summarySection
                WorkoutVitalsSection(start: workout.safeStart, end: workout.safeEnd)
                if !isEditing { notesSection }
                sessionSection
                exercisesSection
            }
            .padding(.horizontal, LiteweightTheme.horizontalPadding)
        }
        .coordinateSpace(name: "workoutDetailScroll")
        .contentMargins(.bottom, LiteweightTheme.floatingWorkoutBottomClearance, for: .scrollContent)
        .background(LiteweightTheme.background.ignoresSafeArea())
        // Keep the full navigation identity for VoiceOver even when its visual title is hidden.
        .navigationTitle(workout.displayTitle(in: exerciseStore.exercises))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                navigationTitleView
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion)) {
                        isEditing.toggle()
                    }
                }
                .accessibilityLabel(isEditing ? "Done Editing Workout" : "Edit Workout")
                Menu {
                    Button("Share", systemImage: "square.and.arrow.up", action: shareWorkout)
                    Divider()
                    Button("Repeat", systemImage: "arrow.clockwise") { repeatWorkout(blank: false) }
                    Button("Repeat with Blank Sets", systemImage: "doc") { repeatWorkout(blank: true) }
                    Divider()
                    Button("Delete Workout", systemImage: "trash", role: .destructive) { workoutToDelete = workout }
                } label: {
                    Label("Workout Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingExerciseSelectorSheet) {
            AddExercisesSheet(
                exercises: exerciseStore.shownExercises,
                recentExercises: AddExercisesSheet.loadRecentExercises(
                    context: managedObjectContext,
                    exercises: exerciseStore.shownExercises
                ),
                shouldDismiss: { persistenceError == nil },
                onAdd: addExercises
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .alert("Workout Not Saved", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "Please try again.")
            }
        }
        .sheet(isPresented: $showingDetailsEditor) {
            CompletedWorkoutDetailsEditor(
                title: workout.displayTitle(in: exerciseStore.exercises),
                comment: workout.comment ?? "",
                effort: workout.sessionEffortValue,
                start: workout.safeStart,
                end: workout.safeEnd,
                persistenceError: $persistenceError,
                onCancel: { showingDetailsEditor = false },
                onSave: { title, comment, effort, start, end in
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    performMutation(
                        failureMessage: "The workout details were not updated."
                    ) {
                        workout.title = trimmedTitle.isEmpty ? nil : trimmedTitle
                        workout.comment = trimmedComment.isEmpty ? nil : trimmedComment
                        workout.sessionEffortValue = effort
                        workout.safeStart = start
                        workout.safeEnd = end
                    } onSuccess: {
                        HealthManager.shared.syncWorkoutEffort(workout: workout)
                        showingDetailsEditor = false
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showingMediaPreview) {
            workoutMediaPreview
        }
        .alert("Workout Not Saved", isPresented: Binding(
            get: {
                persistenceError != nil
                    && !showingExerciseSelectorSheet
                    && !showingDetailsEditor
            },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
        }
        .confirmationDialog(
            "Remove exercise?",
            isPresented: Binding(
                get: { workoutExerciseToDelete != nil },
                set: { if !$0 { workoutExerciseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                guard let workoutExercise = workoutExerciseToDelete else { return }
                workoutExerciseToDelete = nil
                delete(workoutExercise)
            }
            Button("Cancel", role: .cancel) {
                workoutExerciseToDelete = nil
            }
        } message: {
            Text("The exercise and every logged set beneath it will be removed from this workout.")
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(
                get: { workoutToDelete != nil },
                set: { if !$0 { workoutToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) {
                guard let workout = workoutToDelete else { return }
                workoutToDelete = nil
                do {
                    try workout.delete()
                    dismiss()
                } catch {
                    persistenceError = "The workout was not deleted. \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {
                workoutToDelete = nil
            }
        } message: {
            Text(workout.healthExportEligibility != .eligible
                ? "This removes the workout and every logged set from liteweight."
                : "This removes the workout, every logged set, and liteweight's matching Apple Health workout.")
        }
        .sheet(isPresented: $showingRepeatBlocked) {
            WorkoutRepeatBlockedSheet()
        }
        .sensoryFeedback(.error, trigger: showingRepeatBlocked) { _, blocked in blocked }
        .sheet(isPresented: $showingShareUnavailable) {
            LiteweightStatusSheet(
                headerTitle: "Share workout",
                title: "Nothing to share yet",
                message: "This workout does not contain a completed set log. Add or complete a set before sharing it.",
                systemImage: "square.and.arrow.up",
                tint: LiteweightTheme.accent,
                actionTitle: "Got It"
            )
            .presentationDetents([.height(390), .medium])
            .presentationDragIndicator(.visible)
        }
        .liteweightActivitySheet(activityItems: $activityItems)
        .onDisappear { _ = save() }
    }

    @ViewBuilder
    private var navigationTitleView: some View {
        Text(workout.displayTitle(in: exerciseStore.exercises))
            .font(.headline)
            .lineLimit(1)
            // Fade only the ink so the title remains available to accessibility.
            .foregroundStyle(LiteweightTheme.primaryText.opacity(showsNavigationTitle ? 1 : 0))
            .accessibilityAddTraits(.isHeader)
            .animation(LiteweightMotion.preferred(LiteweightMotion.fade, reduceMotion: reduceMotion), value: showsNavigationTitle)
    }

    /// Before iOS 18 the header's scroll position isn't tracked, so the title stays visible.
    private var showsNavigationTitle: Bool {
        if #available(iOS 18, *) { return isNavigationTitleVisible }
        return true
    }

    @ViewBuilder
    private var trackedWorkoutTitleHeader: some View {
        if #available(iOS 18, *) {
            workoutTitleHeader
                .onGeometryChange(for: Bool.self) { geometry in
                    geometry.frame(in: .named("workoutDetailScroll")).maxY <= 0
                } action: { isNavigationTitleVisible = $0 }
        } else {
            workoutTitleHeader
        }
    }

    private var workoutTitleHeader: some View {
        Text(workout.displayTitle(in: exerciseStore.exercises))
            .font(.title2.weight(.bold))
            .foregroundStyle(LiteweightTheme.primaryText)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
    }

    /// The logger's summary, kept after finishing: the same metric colors,
    /// columns and body figure, on a card.
    private var summarySection: some View {
        let sets = workout.numberOfCompletedSets ?? 0
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    WorkoutSummaryAccessibleRow(label: "Duration", value: workoutDurationTitle, tint: LiteweightTheme.metricTime)
                        .liteweightStaggeredEntrance(index: 0)
                    WorkoutSummaryAccessibleRow(label: workoutWorkLabel,
                                                value: [workoutVolumeTitle, workoutWorkUnit].compactMap { $0 }.joined(separator: " "),
                                                tint: workoutWorkTint)
                        .liteweightStaggeredEntrance(index: 1)
                    WorkoutSummaryAccessibleRow(label: "Sets", value: "\(sets)", tint: LiteweightTheme.metricSets)
                        .liteweightStaggeredEntrance(index: 2)
                }
            } else {
                GeometryReader { proxy in
                    let mapWidth: CGFloat = 64
                    let metricWidth = max(0, proxy.size.width - mapWidth - 36)
                    HStack(alignment: .top, spacing: 12) {
                        summaryMetric("Duration", value: workoutDurationTitle, tint: LiteweightTheme.metricTime, index: 0)
                            .frame(width: metricWidth * 0.43)
                        summaryMetric(workoutWorkLabel, value: workoutVolumeTitle, unit: workoutWorkUnit, tint: workoutWorkTint,
                                      numericValue: workoutWorkLabel == "Volume" ? workout.trackedCompletedVolume : nil, index: 1)
                            .frame(width: metricWidth * 0.41)
                        summaryMetric("Sets", value: "\(sets)", tint: LiteweightTheme.metricSets,
                                      numericValue: Double(sets), index: 2)
                            .frame(width: metricWidth * 0.16)
                        WorkoutSummaryMuscleFigure(muscles: WorkoutSummaryMuscleFigure.muscles(
                            in: workoutExercises, catalog: exerciseStore.exercises), height: summaryHeight)
                            .frame(width: mapWidth)
                    }
                    .frame(height: proxy.size.height, alignment: .top)
                }
                .frame(height: summaryHeight)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LiteweightTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var workoutDateSubtitle: String {
        let startDate = workout.safeStart.formatted(date: .complete, time: .omitted)
        let startTime = workout.safeStart.formatted(date: .omitted, time: .shortened)
        let endTime = workout.safeEnd.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(workout.safeStart, inSameDayAs: workout.safeEnd) {
            let formatter = DateIntervalFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "\(startDate) · \(formatter.string(from: workout.safeStart, to: workout.safeEnd))"
        }
        let endDate = workout.safeEnd.formatted(date: .complete, time: .omitted)
        return "\(startDate) · \(startTime) – \(endDate) · \(endTime)"
    }

    private var workoutDurationTitle: String {
        LiteweightFormat.duration(workout.safeDuration)
    }

    private var completedTrackingSets: [WorkoutSet] {
        (workout.workoutExercises?.array as? [WorkoutExercise] ?? []).flatMap {
            $0.workoutSets?.array as? [WorkoutSet] ?? []
        }.filter(\.isCompleted)
    }
    private var workoutWorkLabel: String {
        if workout.trackedCompletedVolume > 0 || completedTrackingSets.isEmpty { return "Volume" }
        if completedTrackingSets.contains(where: { $0.trackingType.usesDistance }) { return "Distance" }
        if completedTrackingSets.contains(where: { $0.trackingType.usesDuration }) { return "Set Time" }
        return "Reps"
    }
    private var workoutWorkTint: Color {
        workoutWorkLabel == "Volume" ? LiteweightTheme.metricVolume : (workoutWorkLabel == "Reps" ? LiteweightTheme.metricSets : LiteweightTheme.metricTime)
    }
    private var workoutWorkUnit: String? {
        switch workoutWorkLabel {
        case "Volume": return settingsStore.weightUnit.unit.symbol
        case "Distance": return WorkoutSet.distanceUnit(settingsStore.weightUnit)
        case "Reps": return "reps"
        default: return nil
        }
    }
    private var workoutVolumeTitle: String {
        if workoutWorkLabel == "Distance" {
            let meters = completedTrackingSets.compactMap(\.distanceValue).reduce(0, +)
            let value = WorkoutSet.distanceDisplayValue(meters, weightUnit: settingsStore.weightUnit)
            return value.formatted(.number.precision(.fractionLength(2)))
        }
        if workoutWorkLabel == "Set Time" {
            return SetTrackingType.durationText(completedTrackingSets.compactMap(\.durationValue).reduce(0, +))
        }
        if workoutWorkLabel == "Reps" { return String(completedTrackingSets.reduce(0) { $0 + Int($1.repetitionsValue) }) }
        let volume = WeightUnit.convert(weight: workout.trackedCompletedVolume, from: .metric, to: settingsStore.weightUnit)
        return settingsStore.weightUnit.displayNumberFormatter.string(from: volume as NSNumber) ?? "—"
    }

    private func summaryMetric(
        _ title: String, value: String, unit: String? = nil, tint: Color, numericValue: Double? = nil, index: Int
    ) -> some View {
        WorkoutSummaryMetric(label: title, value: value, tint: tint, unit: unit, numericValue: numericValue)
            .accessibilityElement(children: .combine)
            .liteweightStaggeredEntrance(index: index)
    }

    private func sectionCaption(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(LiteweightTheme.secondaryText)
            .padding(.leading, 16)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Session")
            VStack(alignment: .leading, spacing: 0) {
                effortRow
                Divider()
                detailRow("Saved Workout", value: workout.workoutRoutine?.displayTitle ?? "One-Off Workout")
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    appleHealthRow
                }
                .font(.subheadline)
                .foregroundStyle(LiteweightTheme.secondaryText)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)

                if workoutMediaURL != nil {
                    Divider()
                    Button {
                        showingMediaPreview = true
                    } label: {
                        Label("View Workout Media", systemImage: "photo")
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LiteweightTheme.accent)
                }
            }
            .padding(.horizontal, 16)
            .background(LiteweightTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var effortRow: some View {
        Button {
            showingDetailsEditor = true
        } label: {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Text("Effort")
                    .font(.body)
                    .foregroundStyle(LiteweightTheme.primaryText)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(spacing: 8) {
                    miniEffortGraph
                    effortValue
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var miniEffortGraph: some View {
        EffortLevelBars(rating: Int((workout.sessionEffortValue ?? 0).rounded()),
                        levelGap: 1, tierGap: 3, cornerRadius: 1, inactiveColor: LiteweightTheme.field)
            .frame(width: 64, height: 20)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var effortValue: some View {
        if let effort = workout.sessionEffortValue, effort > 0 {
            (Text("\(Int(effort))/10").font(.liteweightMetric(.body, weight: .semibold))
                .foregroundColor(LiteweightTheme.metricEffort)
             + Text(" · \(effortLabel(for: effort))")
                .font(.subheadline).foregroundColor(LiteweightTheme.secondaryText))
        } else {
            Text("Not Rated").foregroundStyle(LiteweightTheme.secondaryText)
        }
    }

    @ViewBuilder
    private var appleHealthRow: some View {
        if let source = workout.importSource {
            let origin = source == "hevy" ? "Imported from Hevy" : (source == "sample" ? "Sample data" : "Imported workout")
            Label(source == "sample" ? "Sample data · Not sent" : "\(origin) · Not sent to Apple Health", systemImage: "iphone")
        } else if workout.healthExportState == "exported" || workout.healthExportState == "watch" {
            Label("Saved to Apple Health", systemImage: "checkmark.circle")
        } else if workout.healthExportEligibility == .eligible {
            if workout.healthExportState == "pending" {
                HStack {
                    Label("Waiting to save to Apple Health", systemImage: "heart")
                    Spacer()
                    if healthSyncState == .syncing {
                        ProgressView()
                    } else {
                        Button(action: syncWorkoutToHealth) {
                            Text("Retry")
                                .frame(minWidth: LiteweightTheme.controlHeight, minHeight: LiteweightTheme.controlHeight)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.borderless)
                            .foregroundStyle(LiteweightTheme.accent)
                    }
                }
            } else {
                Button(action: syncWorkoutToHealth) {
                    HStack {
                        Label("Save to Apple Health", systemImage: "heart")
                        if healthSyncState == .syncing { Spacer(); ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: LiteweightTheme.controlHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(LiteweightTheme.accent)
                .disabled(healthSyncState == .syncing)
            }
            if healthSyncState == .failed {
                Text("Could not save. Try again when Apple Health is available.")
                    .font(.caption)
                    .foregroundStyle(LiteweightTheme.secondaryText)
            }
        } else {
            Label("Not sent to Apple Health", systemImage: "iphone")
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if let comment = workout.comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionCaption("Notes")
                Text(comment)
                    .font(.body)
                    .foregroundStyle(LiteweightTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(LiteweightTheme.surface, in: RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous))
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(LiteweightTheme.primaryText)
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(LiteweightTheme.secondaryText)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Exercises")
            if isEditing {
                Button {
                    showingDetailsEditor = true
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                        .frame(minHeight: LiteweightTheme.controlHeight)
                }
                .buttonStyle(.bordered)
                .tint(LiteweightTheme.accent)
                .padding(.bottom, 12)
            }
            if workoutExercises.isEmpty {
                ContentUnavailableView(
                    "No Exercises",
                    systemImage: "dumbbell",
                    description: Text(isEditing
                        ? "Add an exercise to record or correct this session."
                        : "This workout has no recorded exercises.")
                )
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(Array(workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                        exerciseRow(workoutExercise, index: index)
                            .liteweightStaggeredEntrance(index: index)
                    }
                }
            }

            if isEditing {
                Button {
                    showingExerciseSelectorSheet = true
                } label: {
                    Label("Add Exercises", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                        .background(LiteweightTheme.accentSoft, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(LiteweightTheme.accent)
                .padding(.top, 16)
            }
        }
    }

    private var workoutMediaURL: URL? {
        guard let workoutUUID = workout.uuid else { return nil }
        return FinishWorkoutMediaStore.existingURL(for: workoutUUID)
    }

    private var workoutMediaIsVideo: Bool {
        guard let url = workoutMediaURL else { return false }
        return Set(["mov", "mp4", "m4v", "avi", "hevc"]).contains(url.pathExtension.lowercased())
    }

    private var workoutMediaPreview: some View {
        ZStack {
            LiteweightTheme.mediaBackdrop.ignoresSafeArea()

            if workoutMediaIsVideo, let url = workoutMediaURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea(edges: .horizontal)
            } else if let url = workoutMediaURL,
                      let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea(edges: .horizontal)
            }

            VStack {
                HStack {
                    Spacer()
                    Button("Close", systemImage: "xmark") { showingMediaPreview = false }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .tint(LiteweightTheme.onMedia)
                }
                .padding()
                Spacer()
            }
        }
    }

    private func effortLabel(for value: Double) -> String {
        EffortTierPalette.tier(for: Int(value.rounded())).title
    }

    private func syncWorkoutToHealth() {
        guard workout.healthExportEligibility == .eligible else { return }
        healthSyncState = .syncing
        HealthManager.shared.syncWorkoutIfNeeded(
            workout: workout,
            exerciseStore: exerciseStore
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    healthSyncState = .synced
                case .failure:
                    healthSyncState = .failed
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(_ workoutExercise: WorkoutExercise, index: Int) -> some View {
        if isEditing {
            NavigationLink {
                WorkoutExerciseDetailView(workoutExercise: workoutExercise)
                    .environmentObject(settingsStore)
            } label: {
                PastWorkoutExerciseCard(workoutExercise: workoutExercise, isEditing: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .contextMenu {
                if index > 0 {
                    Button("Move Earlier", systemImage: "arrow.up") { moveExercise(from: index, to: index - 1) }
                }
                if index < workoutExercises.count - 1 {
                    Button("Move Later", systemImage: "arrow.down") { moveExercise(from: index, to: index + 1) }
                }
                Divider()
                Button("Remove Exercise", systemImage: "trash", role: .destructive) {
                    workoutExerciseToDelete = workoutExercise
                }
            }
        } else {
            PastWorkoutExerciseCard(workoutExercise: workoutExercise, isEditing: false)
        }
    }

    private func workoutSets(for workoutExercise: WorkoutExercise) -> [WorkoutSet] {
        workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []
    }

    private func addExercises(_ selection: [Exercise]) {
        performMutation(failureMessage: "The exercises were not added.") {
            for exercise in selection {
                let workoutExercise = WorkoutExercise.create(context: managedObjectContext)
                workout.addToWorkoutExercises(workoutExercise)
                workoutExercise.exerciseUuid = exercise.uuid
            }
        }
    }

    private func delete(_ workoutExercise: WorkoutExercise) {
        performMutation(failureMessage: "The exercise was not removed.") {
            workout.removeFromWorkoutExercises(workoutExercise)
            managedObjectContext.delete(workoutExercise)
        }
    }

    private func moveExercise(from source: Int, to destination: Int) {
        guard source != destination, workoutExercises.indices.contains(source), workoutExercises.indices.contains(destination) else { return }
        performMutation(failureMessage: "The exercises were not reordered.") {
            var reordered = workoutExercises
            let item = reordered.remove(at: source)
            reordered.insert(item, at: destination)
            workout.workoutExercises = NSOrderedSet(array: reordered)
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try managedObjectContext.save()
            return true
        } catch {
            persistenceError = "Your latest changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    private func performMutation(
        failureMessage: String,
        mutation: () throws -> Void,
        onSuccess: () -> Void = {}
    ) {
        persistenceError = nil
        do {
            try HistoryMutationPersistence.perform(
                context: managedObjectContext,
                mutation: mutation,
                onSuccess: onSuccess
            )
        } catch {
            persistenceError = "\(failureMessage) \(error.localizedDescription)"
        }
    }

    private func shareWorkout() {
        guard let logText = workout.logText(
            in: exerciseStore.exercises,
            weightUnit: settingsStore.weightUnit
        ) else {
            showingShareUnavailable = true
            return
        }
        activityItems = [logText]
    }

    private func repeatWorkout(blank: Bool) {
        do {
            let didStart = try WorkoutRepeater.start(from: workout, blank: blank, sceneState: sceneState)
            if !didStart { showingRepeatBlocked = true }
        } catch {
            persistenceError = "The workout was not started. \(error.localizedDescription)"
        }
    }
}

private struct PastWorkoutExerciseCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @ObservedObject var workoutExercise: WorkoutExercise
    let isEditing: Bool

    private var exercise: Exercise? {
        workoutExercise.exercise(in: exerciseStore.exercises)
    }

    private var sets: [WorkoutSet] {
        workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []
    }

    private var trackingType: SetTrackingType { sets.first?.trackingType ?? workoutExercise.setTrackingType }
    private var columns: [SetTrackingType.Column] {
        let recorded = Set(sets.flatMap { $0.trackingType.columns })
        let ordered: [SetTrackingType.Column] = [.weight, .reps, .distance, .duration]
        return ordered.filter { recorded.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                header
            } else {
                NavigationLink {
                    WorkoutExerciseDetailView(workoutExercise: workoutExercise)
                        .environmentObject(settingsStore)
                } label: {
                    header
                        .frame(minHeight: LiteweightTheme.controlHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if sets.isEmpty {
                Text("No sets")
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .padding(.top, 12)
            } else if isEditing {
                if !dynamicTypeSize.isAccessibilitySize {
                    columnHeaders
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                }
                setRows
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                        if index > 0 { Divider() }
                        PastWorkoutReadOnlySetRow(set: set, number: index + 1)
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(LiteweightTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise?.title ?? "Unknown Exercise")
                    .font(.headline)
                    .foregroundStyle(LiteweightTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let exercise {
                    Text(exercise.equipment.map(\.equipmentTitle).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if workoutExercise.supersetUuid != nil {
                    Label("Superset", systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                }
                if let comment = workoutExercise.comment, !comment.isEmpty {
                    Label(comment, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                        .accessibilityLabel("Notes for this workout: \(comment)")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if sets.contains(where: { $0.isPersonalRecord == true }) {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(LiteweightTheme.metricRecord)
                    .accessibilityLabel("Personal record")
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LiteweightTheme.tertiaryText)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let exercise {
            ExerciseDiagramThumbnail(exercise: exercise, size: 48)
        } else {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(LiteweightTheme.secondaryText)
                .frame(width: 48, height: 48)
                .background(LiteweightTheme.tertiaryFill, in: Circle())
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 6) {
            Text("Set").frame(width: 44)
            ForEach(columns) { column in
                Text(trackingType.header(for: column, weightUnit: settingsStore.weightUnit.unit.symbol,
                                         distanceUnit: WorkoutSet.distanceUnit(settingsStore.weightUnit)))
                    .frame(maxWidth: .infinity)
            }
            Text("RPE").frame(width: 44)
            Image(systemName: "checkmark")
                .frame(width: 36)
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(LiteweightTheme.secondaryText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }

    private var setRows: some View {
        let orderedSets = sets
        return VStack(spacing: 6) {
            ForEach(Array(orderedSets.enumerated()), id: \.element.id) { index, set in
                PastWorkoutSetRow(
                    set: set,
                    index: index,
                    normalNumber: orderedSets.prefix(index + 1).filter { $0.tagValue == nil }.count,
                    columns: columns,
                    isPersonalRecord: set.isPersonalRecord == true
                )
            }
        }
    }
}

private struct PastWorkoutReadOnlySetRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject var set: WorkoutSet
    let number: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.liteweightMetric(.body, weight: .semibold))
                .foregroundStyle(LiteweightTheme.secondaryText)
                .frame(width: 32, alignment: .leading)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    result
                    metadata
                }
            } else {
                result
                Spacer(minLength: 0)
                metadata
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(set.isCompleted ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 4) {
            resultText
                .font(.liteweightMetric(.body, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            let additional = set.additionalTrackingTitle(weightUnit: settingsStore.weightUnit)
            if !additional.isEmpty {
                Text(additional)
                    .font(.liteweightMetric(.footnote, weight: .semibold))
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var resultText: Text {
        var title = AttributedString(set.resultTitle(weightUnit: settingsStore.weightUnit))
        title.foregroundColor = LiteweightTheme.primaryText
        let units = [settingsStore.weightUnit.unit.symbol, WorkoutSet.distanceUnit(settingsStore.weightUnit), "reps", "rep"]
        for unit in units {
            if let range = title.range(of: unit) {
                title[range].foregroundColor = LiteweightTheme.secondaryText
            }
        }
        return Text(title)
    }

    @ViewBuilder
    private var metadata: some View {
        if set.rpeValue != nil || set.tagValue != nil {
            HStack(spacing: 8) {
                if let rpe = set.rpeValue {
                    Text("RPE \(String(format: "%g", rpe))")
                        .font(.liteweightMetric(.subheadline, weight: .semibold))
                        .foregroundStyle(LiteweightTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tag = set.tagValue {
                    Text(tagSymbol(tag))
                        .font(.liteweightMetric(.callout, weight: .semibold))
                        .foregroundStyle(tagTint(tag))
                        .frame(width: 30, height: 30)
                        .background(tagFill(tag), in: Circle())
                }
            }
        }
    }

    private func tagSymbol(_ tag: WorkoutSetTag) -> String {
        switch tag {
        case .warmUp: return "W"
        case .dropSet: return "D"
        case .failure: return "F"
        }
    }

    private func tagTint(_ tag: WorkoutSetTag) -> Color {
        if set.isCompleted { return LiteweightTheme.setFill(for: tag).tint }
        return tag == .warmUp ? LiteweightTheme.metricSets : LiteweightTheme.secondaryText
    }

    private func tagFill(_ tag: WorkoutSetTag) -> Color {
        if !set.isCompleted { return tag == .warmUp ? LiteweightTheme.metricSetsContainer : LiteweightTheme.field }
        switch tag {
        case .warmUp: return LiteweightTheme.setWarmUpContainer
        case .dropSet: return LiteweightTheme.setDropContainer
        case .failure: return LiteweightTheme.setFailureContainer
        }
    }

    private var accessibilitySummary: String {
        var parts = ["Set \(number)"]
        if let tag = set.tagValue { parts.append(tag.title) }
        if let duration = set.durationValue {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.allowedUnits = [.hour, .minute, .second]
            parts.append(formatter.string(from: duration) ?? SetTrackingType.durationText(duration))
        }
        if let distance = set.distanceValue {
            parts.append("Distance " + WorkoutSet.distanceTitle(distance, weightUnit: settingsStore.weightUnit))
        }
        if set.trackingType.usesWeight || set.weightValue > 0 {
            let weight = WeightUnit.convert(weight: set.weightValue, from: .metric, to: settingsStore.weightUnit)
            let value = settingsStore.weightUnit.displayNumberFormatter.string(from: weight as NSNumber) ?? "—"
            let label = set.trackingType == .assistedBodyweight ? "Assistance" : (set.trackingType == .weightedBodyweight ? "Added weight" : "Weight")
            let unit = settingsStore.weightUnit == .metric ? "kilograms" : "pounds"
            parts.append("\(label), \(value) \(unit)")
        }
        if set.trackingType.usesReps || set.repetitionsValue > 0 {
            parts.append("\(set.repetitionsValue) \(set.repetitionsValue == 1 ? "rep" : "reps")")
        }
        if let rpe = set.rpeValue { parts.append("RPE \(String(format: "%g", rpe))") }
        parts.append(set.isCompleted ? "completed" : "not completed")
        if set.isPersonalRecord == true { parts.append("personal record") }
        return parts.joined(separator: ", ")
    }
}

private struct PastWorkoutSetRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject var set: WorkoutSet

    let index: Int
    let normalNumber: Int
    let columns: [SetTrackingType.Column]
    let isPersonalRecord: Bool

    private var fill: (tint: Color, settled: Double, peak: Double) {
        LiteweightTheme.setFill(for: set.tagValue)
    }

    private var valueColor: Color {
        return set.isCompleted ? LiteweightTheme.primaryText : LiteweightTheme.secondaryText
    }

    private var badgeColor: Color {
        if set.isCompleted { return fill.tint }
        if set.tagValue == .warmUp { return LiteweightTheme.metricSets }
        return LiteweightTheme.secondaryText
    }

    private var badgeFill: Color {
        if set.isCompleted {
            switch set.tagValue {
            case .warmUp: return LiteweightTheme.setWarmUpContainer
            case .dropSet: return LiteweightTheme.setDropContainer
            case .failure: return LiteweightTheme.setFailureContainer
            case nil: return LiteweightTheme.accentSoft
            }
        }
        return set.tagValue == .warmUp ? LiteweightTheme.metricSetsContainer : LiteweightTheme.field
    }

    private var setLabel: String {
        switch set.tagValue {
        case .warmUp: return "W"
        case .dropSet: return "D"
        case .failure: return "F"
        case nil: return "\(normalNumber)"
        }
    }

    private var formattedWeight: String {
        let weight = WeightUnit.convert(weight: set.weightValue, from: .metric, to: settingsStore.weightUnit)
        return set.trackingType.weightPrefix + (settingsStore.weightUnit.displayNumberFormatter.string(from: weight as NSNumber) ?? "—")
    }

    private var durationTitle: String {
        guard let duration = set.durationValue else { return "–" }
        return SetTrackingType.durationText(duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleRow
            } else {
                regularRow
            }
            let additional = set.additionalTrackingTitle(weightUnit: settingsStore.weightUnit)
            if !additional.isEmpty {
                Text(additional)
                    .font(.liteweightMetric(.footnote, weight: .semibold))
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .frame(minHeight: 46)
        .background(fill.tint.opacity(set.isCompleted ? fill.settled : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var regularRow: some View {
        HStack(spacing: 6) {
            badge.frame(width: 44)
            ForEach(columns) { column in
                valueBox(value(for: column), showsRecord: isPersonalRecord && column == .reps)
            }
            rpeValue.frame(width: 44)
            completion.frame(width: 36)
        }
    }

    private var accessibleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                badge.frame(width: 44)
                Spacer(minLength: 0)
                Text("RPE").font(.caption).foregroundStyle(LiteweightTheme.secondaryText)
                rpeValue
                completion.frame(width: 36)
            }
            ForEach(columns) { column in
                accessibleField(set.trackingType.header(for: column, weightUnit: settingsStore.weightUnit.unit.symbol,
                                                       distanceUnit: WorkoutSet.distanceUnit(settingsStore.weightUnit)),
                                value: value(for: column), showsRecord: isPersonalRecord && column == .reps)
            }
        }
        .padding(.vertical, 4)
    }

    private func value(for column: SetTrackingType.Column) -> String {
        guard set.trackingType.columns.contains(column) else { return "—" }
        switch column {
        case .weight: return formattedWeight
        case .reps: return "\(set.repetitionsValue)"
        case .duration: return durationTitle
        case .distance:
            guard let meters = set.distanceValue else { return "—" }
            return WorkoutSet.distanceDisplayValue(meters, weightUnit: settingsStore.weightUnit).formatted(.number.precision(.fractionLength(2)))
        }
    }

    private var badge: some View {
        Text(setLabel)
            .font(.liteweightMetric(.callout, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(badgeColor)
            .frame(width: 30, height: 30)
            .background(badgeFill, in: Circle())
    }

    private func accessibleField(_ title: String, value: String, showsRecord: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(LiteweightTheme.secondaryText)
            valueBox(value, showsRecord: showsRecord)
        }
    }

    private func valueBox(_ value: String, showsRecord: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.liteweightMetric(.title3, weight: .semibold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showsRecord {
                Image(systemName: "trophy.fill")
                    .font(.caption2)
                    .foregroundStyle(LiteweightTheme.metricRecord)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(LiteweightTheme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rpeValue: some View {
        Text(set.rpeValue.map { String(format: "%g", $0) } ?? "–")
            .font(.liteweightMetric(.subheadline, weight: .semibold))
            .foregroundStyle(set.rpeValue == nil || !set.isCompleted ? LiteweightTheme.secondaryText : LiteweightTheme.metricEffort)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var completion: some View {
        Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.palette)
            .foregroundStyle(set.isCompleted ? LiteweightTheme.onAccent : LiteweightTheme.tertiaryText, LiteweightTheme.accent)
            .font(.system(size: 26, weight: .semibold))
    }

    private var accessibilitySummary: String {
        let number = set.tagValue == nil ? normalNumber : index + 1
        var parts = ["Set \(number)"]
        if let tag = set.tagValue { parts.append(tag.title) }
        if let duration = set.durationValue {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.allowedUnits = [.hour, .minute, .second]
            parts.append(formatter.string(from: duration) ?? durationTitle)
        }
        if let distance = set.distanceValue {
            parts.append("Distance " + WorkoutSet.distanceTitle(distance, weightUnit: settingsStore.weightUnit))
        }
        if set.trackingType.usesWeight || set.weightValue > 0 {
            let label = set.trackingType == .assistedBodyweight ? "Assistance" : (set.trackingType == .weightedBodyweight ? "Added weight" : "Weight")
            let unit = settingsStore.weightUnit == .metric ? "kilograms" : "pounds"
            parts.append("\(label), \(formattedWeight) \(unit)")
        }
        if set.trackingType.usesReps || set.repetitionsValue > 0 {
            parts.append("\(set.repetitionsValue) \(set.repetitionsValue == 1 ? "rep" : "reps")")
        }
        if let rpe = set.rpeValue { parts.append("RPE \(String(format: "%g", rpe))") }
        parts.append(set.isCompleted ? "completed" : "not completed")
        if isPersonalRecord { parts.append("personal record") }
        return parts.joined(separator: ", ")
    }
}

private enum WorkoutHealthSyncState: Equatable {
    case idle
    case syncing
    case synced
    case failed
}

private struct CompletedWorkoutDetailsEditor: View {
    @State private var title: String
    @State private var comment: String
    @State private var effort: Double?
    @State private var start: Date
    @State private var end: Date
    @Binding private var persistenceError: String?

    let onCancel: () -> Void
    let onSave: (String, String, Double?, Date, Date) -> Void

    init(
        title: String,
        comment: String,
        effort: Double?,
        start: Date,
        end: Date,
        persistenceError: Binding<String?>,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, Double?, Date, Date) -> Void
    ) {
        _title = State(initialValue: title)
        _comment = State(initialValue: comment)
        _effort = State(initialValue: effort)
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        _persistenceError = persistenceError
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Notes", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Workout Details")
                } footer: {
                    Text("Keep the name and notes useful for future you.")
                }

                Section {
                    EffortRatingGraph(
                        rating: Binding(
                            get: { effort.map { Int($0.rounded()) } ?? 0 },
                            set: { effort = $0 == 0 ? nil : Double($0) }
                        ),
                        allowsUnrated: true
                    )
                    .padding(.vertical, 4)
                } header: {
                    Text("Session Effort")
                } footer: {
                    if effort == nil {
                        Text("Leave unrated, or drag across the graph.")
                    }
                }

                Section {
                    DatePicker(
                        "Started",
                        selection: $start,
                        in: Date.distantPast...min(end, Date()),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Finished",
                        selection: $end,
                        in: min(start, Date())...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Timing")
                } footer: {
                    Text("Duration \(Workout.durationFormatter.string(from: end.timeIntervalSince(start)) ?? "—")")
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") { onSave(title, comment, effort, start, end) }
                        .fontWeight(.semibold)
                }
            }
            .alert("Workout Not Saved", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "Please try again.")
            }
        }
    }
}

// MARK: Actions
extension WorkoutDetailView {
    // Keep HistoryView's existing entry points without duplicating the start path.
    @discardableResult
    static func repeatWorkout(workout: Workout, settingsStore: SettingsStore, sceneState: SceneState) throws -> Bool {
        try WorkoutRepeater.start(from: workout, blank: false, sceneState: sceneState)
    }

    @discardableResult
    static func repeatWorkoutBlank(workout: Workout, settingsStore: SettingsStore, sceneState: SceneState) throws -> Bool {
        try WorkoutRepeater.start(from: workout, blank: true, sceneState: sceneState)
    }
}

#if DEBUG
struct WorkoutDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WorkoutDetailView(workout: MockWorkoutData.metricRandom.workout)
                .mockEnvironment(weightUnit: .metric)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
