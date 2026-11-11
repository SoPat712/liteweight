//
//  ExerciseCategoryView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 04.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import UIKit
import Combine
import WorkoutDataKit

enum ExerciseFilterText {
    static func names(muscleGroup: String?, equipment: String?) -> [String] {
        [muscleGroup?.capitalized, equipment?.equipmentTitle].compactMap { $0 }
    }

    static func searchPrompt(muscleGroup: String?, equipment: String?) -> String {
        let names = names(muscleGroup: muscleGroup, equipment: equipment)
        return names.isEmpty ? "Search exercises" : "Search " + names.joined(separator: " · ")
    }
}

struct ExerciseFilterMenu: View {
    @Binding var muscleGroup: String?
    @Binding var equipment: String?
    let muscleGroups: [String]
    let equipmentOptions: [String]

    private var isActive: Bool {
        muscleGroup != nil || equipment != nil
    }

    var body: some View {
        Menu {
            Picker("Muscle", selection: $muscleGroup) {
                Text("All Muscles").tag(String?.none)
                ForEach(muscleGroups, id: \.self) { group in
                    Text(group.capitalized).tag(String?.some(group))
                }
            }
            .pickerStyle(.menu)

            Picker("Equipment", selection: $equipment) {
                Text("All Equipment").tag(String?.none)
                ForEach(equipmentOptions, id: \.self) { item in
                    Text(item.equipmentTitle).tag(String?.some(item))
                }
            }
            .pickerStyle(.menu)

            if isActive {
                Divider()
                Button {
                    muscleGroup = nil
                    equipment = nil
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .foregroundStyle(isActive ? LiteweightTheme.accent : LiteweightTheme.primaryText)
        }
        .accessibilityLabel("Filters")
        .accessibilityValue(isActive
                            ? ExerciseFilterText.names(muscleGroup: muscleGroup, equipment: equipment).joined(separator: ", ")
                            : "None")
    }
}

struct ExerciseActiveFilterChips: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var muscleGroup: String?
    @Binding var equipment: String?

    var body: some View {
        if muscleGroup != nil || equipment != nil {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        chips
                    }
                } else {
                    HStack(spacing: 8) {
                        chips
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var chips: some View {
        if let muscleGroup {
            chip(muscleGroup.capitalized) { self.muscleGroup = nil }
        }
        if let equipment {
            chip(equipment.equipmentTitle) { self.equipment = nil }
        }
    }

    private func chip(_ name: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(name)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(LiteweightTheme.accent)
        .frame(minHeight: LiteweightTheme.controlHeight)
        .accessibilityLabel("Remove \(name) filter")
    }
}

struct ExerciseMuscleGroupsView : View {
    @EnvironmentObject var exerciseStore: ExerciseStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.managedObjectContext) private var managedObjectContext
    @ObservedObject private var historyStore = TrainingHistoryStore.shared

    @State private var search = ""
    @State private var selectedMuscleGroup: String? = nil
    @State private var selectedEquipment: String? = nil
    @State private var showingCreateExercise = false
    @StateObject private var catalogSearch = ExerciseCatalogSearch()
    @Namespace private var zoomNamespace

    private var hasActiveFilter: Bool {
        selectedMuscleGroup != nil || selectedEquipment != nil
    }

    var body: some View {
        indexedExerciseList
        .listStyle(.insetGrouped)
        .modifier(ExerciseLibraryChrome())
        .onAppear { refreshCatalog() }
        .task { historyStore.observe(in: managedObjectContext) }
        .onReceive(exerciseStore.objectWillChange) { _ in
            // Read the published history after storage, even if this render replaces the subscription.
            DispatchQueue.main.async { refreshCatalog() }
        }
        .onChange(of: [selectedMuscleGroup, selectedEquipment]) { _ in
            catalogSearch.applyFilters(muscleGroup: selectedMuscleGroup, equipment: selectedEquipment)
            if SettingsStore.shared.workoutHaptics {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .task(id: catalogSearch.request(for: search)) {
            await catalogSearch.search(search)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 28)
        }
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                ExerciseFilterMenu(
                    muscleGroup: $selectedMuscleGroup,
                    equipment: $selectedEquipment,
                    muscleGroups: catalogSearch.catalog?.muscleGroups ?? [],
                    equipmentOptions: catalogSearch.catalog?.equipment ?? [])
                Button {
                    showingCreateExercise = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Exercise")
            }
        }
        .titleRowSearchable(text: $search, prompt: ExerciseFilterText.searchPrompt(
            muscleGroup: selectedMuscleGroup, equipment: selectedEquipment))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .sheet(isPresented: $showingCreateExercise) {
            let sheet = CreateCustomExerciseSheet(onDismiss: { showingCreateExercise = false })
                .environmentObject(exerciseStore)
            if #available(iOS 16, *) {
                sheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            } else {
                sheet
            }
        }
    }

    /// The tab's voice: the most-trained exercise of the last 30 days and its heaviest set,
    /// when that set is recent too (build 121). Nothing trained in 30 days: no line.
    private var voiceLine: String? {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let snapshot = historyStore.snapshot
        let entries = snapshot.sessions.flatMap { session in
            session.exercises.map { (date: session.date, exercise: $0.uuid, sets: $0.setCount) }
        }
        guard let leader = TabVoiceLine.busiestExercise(entries, since: since),
              let exercise = exerciseStore.exercisesByUUID[leader.id] else { return nil }
        var heaviest: String?
        if let best = snapshot.exerciseBests[leader.id]?.heaviest, best.date >= since, best.repetitions > 0 {
            let unit = settingsStore.weightUnit
            let value = WeightUnit.convert(weight: best.weight, from: .metric, to: unit)
            heaviest = (unit.displayNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)")
                + " \(unit.unit.symbol) × \(best.repetitions)"
        }
        return TabVoiceLine.exercises(leader: exercise.title, sets: leader.sets, heaviest: heaviest)
    }

    private func refreshCatalog() {
        catalogSearch.refresh(exercises: exerciseStore.shownExercises, store: exerciseStore,
                              muscleGroup: selectedMuscleGroup, equipment: selectedEquipment)
    }

    @ViewBuilder
    private var indexedExerciseList: some View {
        if #available(iOS 26, *) {
            exerciseList
                .listSectionIndexVisibility(.visible)
        } else {
            exerciseList
        }
    }

    private var exerciseList: some View {
        let candidates = catalogSearch.candidates
        let results = catalogSearch.listing(for: search, showingAll: true).exercises
        return List {
            if search.isEmpty {
                if !hasActiveFilter, let voice = voiceLine {
                    LiteweightVoiceSection(text: TabVoiceLine.text(voice))
                }
                if hasActiveFilter {
                    filterRow
                }
                if let candidates {
                    if candidates.exercises.isEmpty {
                        emptyExerciseState
                    } else {
                        if !candidates.recent.isEmpty {
                            Section("Recent") {
                                exerciseRows(candidates.recent)
                            }
                        }
                        ForEach(candidates.sections, id: \.letter) { section in
                            letterSection(section.letter, exercises: section.exercises)
                        }
                    }
                }
            } else {
                Section {
                    if results.isEmpty && catalogSearch.isSearching(search) {
                        ProgressView("Searching Exercises…")
                    } else if results.isEmpty {
                        emptyExerciseState
                    } else {
                        exerciseRows(results)
                    }
                } header: {
                    // A separate, headerless filter section reserved a large gap
                    // before search results. Keep the filters in this header instead.
                    if hasActiveFilter {
                        ExerciseActiveFilterChips(muscleGroup: $selectedMuscleGroup, equipment: $selectedEquipment)
                            .textCase(nil)
                            .padding(.bottom, 8)
                    }
                }
            }

            Section {
                NavigationLink(destination: CustomExercisesView()) {
                    libraryRowLabel("Custom Exercises", count: catalogSearch.catalog?.customCount ?? 0)
                }
                NavigationLink(destination: HiddenExercisesView()) {
                    libraryRowLabel("Hidden Exercises", count: catalogSearch.catalog?.hiddenCount ?? 0)
                }
            } header: {
                Text("Library")
            } footer: {
                exerciseCountFooter(search.isEmpty ? candidates?.exercises.count ?? 0 : results.count)
            }
        }
        .modifier(ExerciseLibraryScrollEdge())
    }

    @ViewBuilder
    private func letterSection(_ letter: String, exercises: [Exercise]) -> some View {
        let section = Section(letter) {
            exerciseRows(exercises)
        }

        if #available(iOS 26, *) {
            section.sectionIndexLabel(letter)
        } else {
            section
        }
    }

    private func exerciseRows(_ exercises: [Exercise]) -> some View {
        ForEach(exercises) { exercise in
            NavigationLink {
                ExerciseDetailView(exercise: exercise)
                    .liteweightZoomDestination(id: exercise.uuid, in: zoomNamespace)
            } label: {
                ExerciseLibraryRow(exercise: exercise)
                    .liteweightZoomSource(id: exercise.uuid, in: zoomNamespace)
            }
        }
    }

    private func exerciseCountFooter(_ count: Int) -> some View {
        Text("^[\(count) exercise](inflect: true)")
            .font(.liteweightMetric(.footnote, weight: .semibold))
            .foregroundStyle(LiteweightTheme.secondaryText)
    }

    private func libraryRowLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(LiteweightTheme.primaryText)
            Spacer()
            Text(count.formatted())
                .font(.liteweightMetric(.body, weight: .semibold))
                .foregroundStyle(LiteweightTheme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("^[\(count) exercise](inflect: true)")
    }

    @ViewBuilder
    private var filterRow: some View {
        let section = Section {
            ExerciseActiveFilterChips(muscleGroup: $selectedMuscleGroup, equipment: $selectedEquipment)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        if #available(iOS 17, *) {
            // A standalone filter section otherwise adds a grouped-list gap
            // before the first exercise header.
            section.listSectionSpacing(0)
        } else {
            section
        }
    }

    @ViewBuilder
    private var emptyExerciseState: some View {
        let hasSearch = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if #available(iOS 17, *) {
            if hasSearch {
                ContentUnavailableView.search(text: search)
            } else {
                ContentUnavailableView {
                    emptyExerciseLabel
                } description: {
                    emptyExerciseDescription
                } actions: {
                    if hasActiveFilter {
                        Button("Clear Filters") {
                            selectedEquipment = nil
                            selectedMuscleGroup = nil
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                if hasSearch {
                    Text("No results for \"\(search)\"")
                        .font(.headline)
                } else {
                    emptyExerciseLabel
                        .font(.headline)
                    emptyExerciseDescription
                        .font(.subheadline)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                    if hasActiveFilter {
                        Button("Clear Filters") {
                            selectedEquipment = nil
                            selectedMuscleGroup = nil
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var emptyExerciseLabel: some View {
        if hasActiveFilter {
            Label("No matching exercises", systemImage: "line.3.horizontal.decrease")
        } else {
            Label("No exercises available", systemImage: "eye.slash")
        }
    }

    @ViewBuilder
    private var emptyExerciseDescription: some View {
        if hasActiveFilter {
            Text("Try a different muscle group or equipment.")
        } else {
            Text("All exercises are hidden. Restore one from Hidden Exercises in the Library section.")
        }
    }
}

private struct ExerciseLibraryScrollEdge: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // Translucent: rows soften under the pinned search instead of meeting a solid band.
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct ExerciseLibraryChrome: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .contentMargins(.top, 0, for: .scrollContent)
                .toolbarTitleDisplayMode(.inlineLarge)
        } else {
            content.navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct HiddenExercisesView: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore

    @State private var search = ""

    private var filteredExercises: [Exercise] {
        let candidates = exerciseStore.hiddenExercises
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return ExerciseStore.filter(exercises: exerciseStore.orderedByRecency(candidates), using: search,
                                    lastPerformedDates: exerciseStore.lastPerformedDates)
    }

    var body: some View {
        List {
            if filteredExercises.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(filteredExercises) { exercise in
                        hiddenExerciseRow(exercise)
                    }
                } footer: {
                    Text("\(filteredExercises.count) hidden exercises")
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 28)
        }
        .navigationTitle("Hidden exercises")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search hidden exercises")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func hiddenExerciseRow(_ exercise: Exercise) -> some View {
        NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
            ExerciseLibraryRow(exercise: exercise)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                exerciseStore.show(exercise: exercise)
            } label: {
                Label("Restore", systemImage: "eye")
            }
            .tint(.accentColor)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let hasSearch = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if #available(iOS 17, *) {
            if hasSearch {
                ContentUnavailableView.search(text: search)
            } else {
                ContentUnavailableView {
                    Label("No hidden exercises", systemImage: "eye")
                } description: {
                    Text("Exercises you hide from the library will appear here.")
                }
            }
        } else {
            VStack(spacing: 8) {
                if hasSearch {
                    Text("No results for \"\(search)\"")
                        .font(.headline)
                } else {
                    Label("No hidden exercises", systemImage: "eye")
                        .font(.headline)
                    Text("Exercises you hide from the library will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct AllExercisesView: View {
    @ObservedObject private var filter: ExerciseGroupFilter
    
    init(exerciseGroups: [ExerciseGroup]) {
        self.filter = ExerciseGroupFilter(exerciseGroups: exerciseGroups)
    }
    
    var body: some View {
        MuscleGroupSectionedExercisesView(exerciseGroups: filter.exerciseGroups)
            .navigationTitle("All exercises")
        .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.filter, prompt: "Search exercises")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

#if DEBUG
struct ExerciseCategoryView_Previews : PreviewProvider {
    static var previews: some View {
        ExerciseMuscleGroupsView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
