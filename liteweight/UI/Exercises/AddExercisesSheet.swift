//
//  AddExercisesSheet.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 03.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import UIKit
import Combine
import WorkoutDataKit
import CoreData

/// Query-independent library data, rebuilt only for catalog/history changes.
/// Both exercise lists use the same prepared text and browse/search ordering.
final class AddExerciseCatalog {
    /// Exercise is an immutable value, but its module does not declare Sendable.
    /// Copy its fields rather than sending the store or any managed objects.
    struct ExerciseSnapshot: Sendable {
        let uuid: UUID
        let everkineticId: Int
        let title: String
        let originalTitle: String
        let alias: [String]
        let description: String?
        let primaryMuscle: [String]
        let secondaryMuscle: [String]
        let equipment: [String]
        let steps: [String]
        let tips: [String]
        let references: [String]
        let pdfPaths: [String]
        let imageFilename: String?
        let animationFilename: String?

        init(_ exercise: Exercise) {
            uuid = exercise.uuid
            everkineticId = exercise.everkineticId
            title = exercise.title
            originalTitle = exercise.originalTitle
            alias = exercise.alias
            description = exercise.description
            primaryMuscle = exercise.primaryMuscle
            secondaryMuscle = exercise.secondaryMuscle
            equipment = exercise.equipment
            steps = exercise.steps
            tips = exercise.tips
            references = exercise.references
            pdfPaths = exercise.pdfPaths
            imageFilename = exercise.imageFilename
            animationFilename = exercise.animationFilename
        }

        var exercise: Exercise {
            Exercise(uuid: uuid, everkineticId: everkineticId, title: title, alias: alias,
                     description: description, primaryMuscle: primaryMuscle, secondaryMuscle: secondaryMuscle,
                     equipment: equipment, steps: steps, tips: tips, references: references, pdfPaths: pdfPaths,
                     imageFilename: imageFilename, animationFilename: animationFilename, originalTitle: originalTitle)
        }
    }

    struct Snapshot: Sendable {
        let exercises: [ExerciseSnapshot]
        let lastPerformedDates: [UUID: Date]
        let browsableIDs: Set<UUID>
        let customCount: Int
        let hiddenCount: Int
        let ordersByRecency: Bool

        init(exercises: [Exercise], store: ExerciseStore, ordersByRecency: Bool = false) {
            self.exercises = exercises.map(ExerciseSnapshot.init)
            lastPerformedDates = store.lastPerformedDates
            browsableIDs = Set(exercises.filter(store.isBrowsable).map(\.uuid))
            customCount = store.customExercises.count
            hiddenCount = max(store.exercises.count - exercises.count, 0)
            self.ordersByRecency = ordersByRecency
        }
    }

    struct RowDisplay: Sendable {
        let title: String
        let accessibilityLabel: String
        let hasPlayableDemonstration: Bool
    }

    fileprivate struct Entry: Sendable {
        let id: UUID
        let title: String
        let muscleGroup: String
        let equipment: [String]
        let prepared: ExerciseSearch.Prepared<UUID>
        let isBrowsable: Bool
        let details: [String]
        var display: RowDisplay
    }

    fileprivate struct ListingSnapshot: Sendable {
        let ids: [UUID]
        let recent: [UUID]
        let remaining: [UUID]
        let moreCount: Int
    }

    fileprivate struct LetterSnapshot: Sendable {
        let letter: String
        let ids: [UUID]
    }

    fileprivate struct CandidateSnapshot: Sendable {
        let ids: [UUID]
        let recent: [UUID]
        let sections: [LetterSnapshot]
        let collapsed: ListingSnapshot
        let expanded: ListingSnapshot
        let searchInput: SearchInput
    }

    struct Preparation: Sendable {
        fileprivate private(set) var entries: [Entry]
        private let alphabetical: [Entry]
        fileprivate let unfiltered: CandidateSnapshot
        fileprivate private(set) var captions: [Date: String]
        let lastPerformedDates: [UUID: Date]
        let muscleGroups: [String]
        let equipment: [String]
        let equipmentCounts: [String: Int]
        let customCount: Int
        let hiddenCount: Int

        init(snapshot: Snapshot) {
            let captured = snapshot.exercises.map(\.exercise)
            let exercises = snapshot.ordersByRecency
                ? ExerciseRecency.ordered(captured, dates: snapshot.lastPerformedDates) : captured
            let sorted = exercises.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            lastPerformedDates = snapshot.lastPerformedDates
            let captions = Self.captions(dates: snapshot.lastPerformedDates)
            self.captions = captions

            let entries = ExerciseRecency.ordered(sorted, dates: snapshot.lastPerformedDates).map { exercise in
                let muscleTitle = exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized
                let details = [muscleTitle, exercise.equipment.first?.equipmentTitle].compactMap { $0 }
                let recency = snapshot.lastPerformedDates[exercise.uuid].flatMap { captions[$0] }
                let display = Self.display(title: exercise.title, details: details, recency: recency,
                                           hasPlayableDemonstration: exercise.hasPlayableDemonstration)
                return Entry(id: exercise.uuid, title: exercise.title, muscleGroup: exercise.muscleGroup,
                             equipment: exercise.equipment, prepared: ExerciseSearch.Prepared(
                                id: exercise.uuid, title: exercise.title, aliases: exercise.alias,
                                originalTitle: exercise.originalTitle),
                             isBrowsable: snapshot.browsableIDs.contains(exercise.uuid), details: details, display: display)
            }
            self.entries = entries
            let alphabetical = entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            self.alphabetical = alphabetical
            unfiltered = Self.candidates(entries: entries, alphabetical: alphabetical,
                                         dates: snapshot.lastPerformedDates, muscleGroup: nil, equipment: nil)
            muscleGroups = Array(Set(entries.map(\.muscleGroup))).sorted()
            var counts: [String: Int] = [:]
            exercises.forEach { exercise in
                exercise.equipment.forEach { counts[$0, default: 0] += 1 }
            }
            equipmentCounts = counts
            equipment = counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
            customCount = snapshot.customCount
            hiddenCount = snapshot.hiddenCount
        }

        func refreshingCaptions() -> Preparation {
            let captions = Self.captions(dates: lastPerformedDates)
            guard captions != self.captions else { return self }
            var refreshed = self
            refreshed.captions = captions
            refreshed.entries = entries.map { entry in
                var entry = entry
                let recency = lastPerformedDates[entry.id].flatMap { captions[$0] }
                entry.display = Self.display(title: entry.title, details: entry.details, recency: recency,
                                             hasPlayableDemonstration: entry.display.hasPlayableDemonstration)
                return entry
            }
            return refreshed
        }

        private static func captions(dates: [UUID: Date]) -> [Date: String] {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            let calendar = Calendar.current
            let now = Date()
            let today = calendar.startOfDay(for: now)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
            var captions: [Date: String] = [:]
            for date in Set(dates.values) {
                if calendar.isDate(date, inSameDayAs: today) {
                    captions[date] = "Today"
                } else if let yesterday, calendar.isDate(date, inSameDayAs: yesterday) {
                    captions[date] = "Yesterday"
                } else {
                    captions[date] = formatter.localizedString(for: date, relativeTo: now)
                }
            }
            return captions
        }

        private static func display(title: String, details: [String], recency: String?,
                                    hasPlayableDemonstration: Bool) -> RowDisplay {
            RowDisplay(title: (details + (recency.map { [$0] } ?? [])).joined(separator: " · "),
                       accessibilityLabel: ([title] + details
                        + (recency.map { ["last done \($0.lowercased())"] } ?? [])).joined(separator: ", "),
                       hasPlayableDemonstration: hasPlayableDemonstration)
        }

        fileprivate func candidates(muscleGroup: String?, equipment: String?) -> CandidateSnapshot {
            Self.candidates(entries: entries, alphabetical: alphabetical, dates: lastPerformedDates,
                            muscleGroup: muscleGroup, equipment: equipment)
        }

        private static func candidates(entries: [Entry], alphabetical: [Entry], dates: [UUID: Date],
                                       muscleGroup: String?, equipment: String?) -> CandidateSnapshot {
            let filtered = entries.filter { entry in
                (muscleGroup == nil || entry.muscleGroup == muscleGroup)
                    && (equipment.map { entry.equipment.contains($0) } ?? true)
            }
            let ids = filtered.map(\.id)
            let browsable = filtered.filter(\.isBrowsable).map(\.id)
            let secondary = filtered.filter { !$0.isBrowsable }.map(\.id)
            let collapsed = browsable.isEmpty ? ids : browsable
            let filteredIDs = Set(ids)
            let groups = Dictionary(grouping: alphabetical.filter { filteredIDs.contains($0.id) }) { entry in
                let initial = String(entry.title.prefix(1)).uppercased()
                return initial.count == 1 && "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(initial) ? initial : "#"
            }
            let sections = groups.keys.sorted {
                if $0 == "#" { return false }
                if $1 == "#" { return true }
                return $0 < $1
            }.map { LetterSnapshot(letter: $0, ids: (groups[$0] ?? []).map(\.id)) }

            func listing(_ listed: [UUID]) -> ListingSnapshot {
                ListingSnapshot(ids: listed, recent: listed.filter { dates[$0] != nil },
                                remaining: listed.filter { dates[$0] == nil }, moreCount: ids.count - listed.count)
            }

            return CandidateSnapshot(
                ids: ids, recent: Array(ids.filter { dates[$0] != nil }.prefix(8)), sections: sections,
                collapsed: listing(collapsed), expanded: listing(browsable + secondary),
                searchInput: SearchInput(prepared: filtered.map(\.prepared), lastPerformedDates: dates,
                                         browsableIDs: Set(browsable)))
        }
    }

    private struct Filters: Hashable {
        let muscleGroup: String?
        let equipment: String?
    }

    struct Row: Identifiable {
        let exercise: Exercise
        let display: RowDisplay
        var id: UUID { exercise.uuid }
    }

    private let preparation: Preparation
    private let rowsByID: [UUID: Row]
    private var cachedCandidates: [Filters: Candidates] = [:]
    var muscleGroups: [String] { preparation.muscleGroups }
    var equipment: [String] { preparation.equipment }
    var equipmentCounts: [String: Int] { preparation.equipmentCounts }
    var customCount: Int { preparation.customCount }
    var hiddenCount: Int { preparation.hiddenCount }
    /// Matching exercises the last result left out until the person asks for more.
    private(set) var moreCount = 0

    convenience init(exercises: [Exercise], store: ExerciseStore) {
        self.init(exercises: exercises, preparation: Preparation(snapshot: Snapshot(exercises: exercises, store: store)))
    }

    init(exercises: [Exercise], preparation: Preparation) {
        self.preparation = preparation
        let exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.uuid, $0) })
        rowsByID = Dictionary(uniqueKeysWithValues: preparation.entries.map { entry in
            (entry.id, Row(exercise: exercisesByID[entry.id]!, display: entry.display))
        })
        cachedCandidates[Filters(muscleGroup: nil, equipment: nil)] = candidates(from: preparation.unfiltered)
    }

    struct Listing {
        let exercises: [Exercise]
        let recent: [Exercise]
        let remaining: [Exercise]
        let moreCount: Int
        let rows: [Row]
        let recentRows: [Row]
        let remainingRows: [Row]

        init(rows: [Row], recent: [Row], remaining: [Row], moreCount: Int) {
            self.rows = rows
            recentRows = recent
            remainingRows = remaining
            exercises = rows.map(\.exercise)
            self.recent = recent.map(\.exercise)
            self.remaining = remaining.map(\.exercise)
            self.moreCount = moreCount
        }

        static let empty = Listing(rows: [], recent: [], remaining: [], moreCount: 0)
    }

    struct LetterSection {
        let letter: String
        let exercises: [Exercise]
    }

    /// Only these immutable, Sendable values cross into a search task.
    struct SearchInput: Sendable {
        let prepared: [ExerciseSearch.Prepared<UUID>]
        let lastPerformedDates: [UUID: Date]
        let browsableIDs: Set<UUID>

        func rankedIDs(matching query: ExerciseSearch.Query) -> [UUID] {
            let matches = ExerciseSearch.ranked(prepared, matching: query, lastPerformedDates: lastPerformedDates)
            // ExerciseStore.listed(showingAll: true) partitions after ranking.
            return matches.filter { browsableIDs.contains($0.id) }.map(\.id)
                + matches.filter { !browsableIDs.contains($0.id) }.map(\.id)
        }
    }

    struct Candidates {
        let revision = UUID()
        let exercises: [Exercise]
        let exercisesByID: [UUID: Exercise]
        let recent: [Exercise]
        let sections: [LetterSection]
        let collapsed: Listing
        let expanded: Listing
        let searchInput: SearchInput
        let rowsByID: [UUID: Row]

        func searchListing(ids: [UUID]) -> Listing {
            Listing(rows: ids.compactMap { rowsByID[$0] }, recent: [], remaining: [], moreCount: 0)
        }
    }

    func candidates(muscleGroup: String?, equipment: String?) -> Candidates {
        let filters = Filters(muscleGroup: muscleGroup, equipment: equipment)
        if let cached = cachedCandidates[filters] { return cached }
        let candidates = candidates(from: preparation.candidates(muscleGroup: muscleGroup, equipment: equipment))
        cachedCandidates[filters] = candidates
        return candidates
    }

    private func candidates(from snapshot: CandidateSnapshot) -> Candidates {
        func rows(_ ids: [UUID]) -> [Row] { ids.compactMap { rowsByID[$0] } }

        func listing(_ snapshot: ListingSnapshot) -> Listing {
            Listing(rows: rows(snapshot.ids), recent: rows(snapshot.recent), remaining: rows(snapshot.remaining),
                    moreCount: snapshot.moreCount)
        }

        let selectedRows = rows(snapshot.ids)
        let exercises = selectedRows.map(\.exercise)
        return Candidates(
            exercises: exercises,
            exercisesByID: Dictionary(uniqueKeysWithValues: exercises.map { ($0.uuid, $0) }),
            recent: rows(snapshot.recent).map(\.exercise),
            sections: snapshot.sections.map { LetterSection(letter: $0.letter, exercises: rows($0.ids).map(\.exercise)) },
            collapsed: listing(snapshot.collapsed), expanded: listing(snapshot.expanded),
            searchInput: snapshot.searchInput,
            rowsByID: Dictionary(uniqueKeysWithValues: selectedRows.map { ($0.id, $0) })
        )
    }

    /// Synchronous entry point retained for ranking parity tests and existing callers.
    /// SwiftUI uses cached Candidates and ExerciseCatalogSearch instead.
    func matches(search: String, muscleGroup: String?, equipment: String?, showingAll: Bool = false) -> [Exercise] {
        let candidates = candidates(muscleGroup: muscleGroup, equipment: equipment)
        let query = ExerciseSearch.Query(search)
        let listing = query.isEmpty
            ? (showingAll ? candidates.expanded : candidates.collapsed)
            : candidates.searchListing(ids: candidates.searchInput.rankedIDs(matching: query))
        moreCount = listing.moreCount
        return listing.exercises
    }
}

@MainActor
private final class AddExerciseCatalogCache {
    static let shared = AddExerciseCatalogCache()

    private struct Key: Equatable {
        let revision: UUID
        let hiddenIDs: Set<UUID>
        let fallback: [Exercise]?
        let locale: String
        let calendar: Calendar
    }

    @MainActor
    final class Preparation {
        let revision = UUID()
        private let exercises: [Exercise]
        private let worker: Task<AddExerciseCatalog.Preparation, Never>
        private var prepared: AddExerciseCatalog.Preparation?
        private var catalog: AddExerciseCatalog?
        private(set) var isCurrent = true

        init(exercises: [Exercise], store: ExerciseStore, ordersByRecency: Bool) {
            self.exercises = exercises
            let snapshot = AddExerciseCatalog.Snapshot(exercises: exercises, store: store,
                                                       ordersByRecency: ordersByRecency)
            worker = Task.detached(priority: .userInitiated) {
                AddExerciseCatalog.Preparation(snapshot: snapshot)
            }
        }

        func value() async -> AddExerciseCatalog {
            let prepared: AddExerciseCatalog.Preparation
            if let previous = self.prepared {
                // Relative labels can change without a history edit. Recheck just
                // those strings off main, retaining search text and browse order.
                prepared = await Task.detached(priority: .userInitiated) {
                    previous.refreshingCaptions()
                }.value
            } else {
                prepared = await worker.value
            }
            if let catalog, self.prepared?.captions == prepared.captions { return catalog }
            let catalog = AddExerciseCatalog(exercises: exercises, preparation: prepared)
            self.prepared = prepared
            self.catalog = catalog
            return catalog
        }

        func invalidate() {
            isCurrent = false
        }
    }

    @MainActor
    private final class StoreRevision {
        weak var store: ExerciseStore?
        var revision = UUID()
        var key: Key?
        var preparation: Preparation?
        private var observation: AnyCancellable?

        init(store: ExerciseStore) {
            self.store = store
            // Keep observing while sheets are dismissed. Every mutable catalog,
            // visibility and history input publishes through this store.
            observation = store.objectWillChange.sink { [weak self] _ in
                self?.preparation?.invalidate()
                self?.revision = UUID()
            }
        }
    }

    private var stores: [ObjectIdentifier: StoreRevision] = [:]

    func preparation(store: ExerciseStore, fallback: [Exercise]) -> Preparation {
        let id = ObjectIdentifier(store)
        let entry: StoreRevision
        if let existing = stores[id], existing.store === store {
            entry = existing
        } else {
            stores = stores.filter { $0.value.store != nil }
            entry = StoreRevision(store: store)
            stores[id] = entry
        }

        // This boundary also refreshes hidden defaults changed by another process.
        // Avoid shownExercises: its recency sort belongs in the detached worker.
        let hidden = store.hiddenExercises
        let hiddenIDs = Set(hidden.map(\.uuid))
        let exercises = store.exercises
        let usesFallback = hidden.count == exercises.count
        let calendar = Calendar.current
        let key = Key(revision: entry.revision, hiddenIDs: hiddenIDs, fallback: usesFallback ? fallback : nil,
                      locale: Locale.current.identifier, calendar: calendar)
        if entry.key == key, let preparation = entry.preparation { return preparation }
        entry.preparation?.invalidate()
        let shown = usesFallback ? fallback : exercises.filter { !hiddenIDs.contains($0.uuid) }
        let preparation = Preparation(exercises: shown, store: store, ordersByRecency: !usesFallback)
        entry.key = key
        entry.preparation = preparation
        return preparation
    }
}

/// Main-actor publication with cancellable debounce; the detached worker sees
/// prepared text, IDs and a history snapshot, never the observable store.
@MainActor
final class ExerciseCatalogSearch: ObservableObject {
    struct Request: Equatable {
        let query: String
        let revision: UUID?
    }

    private struct Source: Equatable {
        let exercises: [Exercise]
        // History changes must invalidate candidates even with identical exercises and filters.
        let dates: [UUID: Date]
        let referencedIDs: Set<UUID>
        let customCount: Int
        let totalCount: Int
    }

    @Published private(set) var catalog: AddExerciseCatalog?
    @Published private(set) var candidates: AddExerciseCatalog.Candidates?
    @Published private(set) var searchResult = AddExerciseCatalog.Listing.empty
    private var completedRequest: Request?
    private var source: Source?
    private var activeFilters: [String?]?
    private var preparationRevision: UUID?
    private var preparationTask: Task<Void, Never>?

    /// "Today" and "Yesterday" move at midnight without a catalog change; the next refresh rechecks them.
    func expireCaptions() {
        preparationRevision = nil
    }

    func refresh(store: ExerciseStore, fallback: [Exercise], muscleGroup: String?, equipment: String?) {
        let preparation = AddExerciseCatalogCache.shared.preparation(store: store, fallback: fallback)
        guard preparationRevision != preparation.revision else {
            applyFilters(muscleGroup: muscleGroup, equipment: equipment)
            return
        }
        preparationRevision = preparation.revision
        preparationTask?.cancel()
        source = nil
        activeFilters = [muscleGroup, equipment]
        preparationTask = Task { [weak self] in
            // The shared worker survives dismissal so the next open can reuse it.
            let catalog = await preparation.value()
            guard !Task.isCancelled, preparation.isCurrent, let self,
                  self.preparationRevision == preparation.revision else { return }
            self.publish(catalog)
        }
    }

    private func publish(_ catalog: AddExerciseCatalog) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.catalog = catalog
            applyFilters(muscleGroup: activeFilters?[0], equipment: activeFilters?[1], force: true)
        }
    }

    func refresh(exercises: [Exercise], store: ExerciseStore, muscleGroup: String?, equipment: String?) {
        let source = Source(exercises: exercises, dates: store.lastPerformedDates,
                            referencedIDs: store.workoutReferencedExerciseIDs,
                            customCount: store.customExercises.count, totalCount: store.exercises.count)
        guard self.source != source else {
            applyFilters(muscleGroup: muscleGroup, equipment: equipment)
            return
        }
        preparationRevision = nil
        preparationTask?.cancel()
        self.source = source
        catalog = AddExerciseCatalog(exercises: exercises, store: store)
        applyFilters(muscleGroup: muscleGroup, equipment: equipment, force: true)
    }

    func applyFilters(muscleGroup: String?, equipment: String?, force: Bool = false) {
        let filters = [muscleGroup, equipment]
        guard force || activeFilters != filters else { return }
        activeFilters = filters
        candidates = catalog?.candidates(muscleGroup: muscleGroup, equipment: equipment)
        completedRequest = nil
        searchResult = .empty
    }

    func request(for query: String) -> Request {
        Request(query: query, revision: candidates?.revision)
    }

    func isSearching(_ query: String) -> Bool {
        !ExerciseSearch.Query(query).isEmpty && completedRequest != request(for: query)
    }

    func listing(for query: String, showingAll: Bool) -> AddExerciseCatalog.Listing {
        guard let candidates else { return .empty }
        if ExerciseSearch.Query(query).isEmpty {
            return showingAll ? candidates.expanded : candidates.collapsed
        }
        return searchResult
    }

    func search(_ text: String) async {
        let request = request(for: text)
        let query = ExerciseSearch.Query(text)
        // Clearing search reads the cached browse lists in the same render.
        guard let candidates, !query.isEmpty else { return }
        do {
            try await Task.sleep(nanoseconds: 120_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        let input = candidates.searchInput
        let worker = Task.detached(priority: .userInitiated) {
            input.rankedIDs(matching: query)
        }
        let ids = await withTaskCancellationHandler(operation: {
            await worker.value
        }, onCancel: {
            worker.cancel()
        })
        guard !Task.isCancelled, self.candidates?.revision == request.revision else { return }
        completedRequest = request
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            searchResult = candidates.searchListing(ids: ids)
        }
    }
}

struct AddExercisesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @ScaledMetric(relativeTo: .subheadline) private var selectionIndicatorSize: CGFloat = 26

    private let exercises: [Exercise]
    private let title: String
    private let actionTitle: String
    private let maximumSelectionCount: Int?
    let onAdd: ([Exercise]) -> Void
    private let onDismiss: (() -> Void)?
    private let shouldDismiss: () -> Bool

    @State private var exerciseSelectorSelection: [Exercise] = []
    @State private var search = ""
    @State private var selectedMuscleGroup: String?
    @State private var selectedEquipment: String?
    @State private var showingAllExercises = false
    @State private var hasExpandedBrowseList = false
    @State private var detailExercise: Exercise?
    @State private var mediaExercise: Exercise?
    @State private var mediaFeedback = 0
    @State private var selectionFeedback = 0
    @State private var showingCreateExercise = false
    @StateObject private var catalogSearch = ExerciseCatalogSearch()

    init(
        exercises: [Exercise],
        recentExercises: [Exercise] = [],
        title: String = "Add Exercise",
        actionTitle: String = "Add",
        maximumSelectionCount: Int? = nil,
        onDismiss: (() -> Void)? = nil,
        shouldDismiss: @escaping () -> Bool = { true },
        onAdd: @escaping ([Exercise]) -> Void
    ) {
        self.exercises = exercises
        // Kept as an initializer argument for existing callers. Recents now
        // come from the live shared cache, rather than a presentation snapshot.
        self.title = title
        self.actionTitle = actionTitle
        self.maximumSelectionCount = maximumSelectionCount
        self.onDismiss = onDismiss
        self.shouldDismiss = shouldDismiss
        self.onAdd = onAdd
    }

    private func refreshCatalog() {
        catalogSearch.refresh(store: exerciseStore, fallback: exercises,
                              muscleGroup: selectedMuscleGroup, equipment: selectedEquipment)
    }

    private func resetAndDismiss() {
        guard shouldDismiss() else { return }
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
        self.exerciseSelectorSelection.removeAll()
        self.search = ""
    }
    
    static func loadRecentExercises(context: NSManagedObjectContext, exercises: [Exercise], maxCount: Int = .max) -> [Exercise] {
        guard maxCount > 0 else { return [] }
        // Compatibility for CurrentWorkoutView and other existing callers.
        // No history fetch runs on presentation or on a search keystroke.
        let store = ExerciseStore.shared
        store.observeWorkoutHistory(in: context)
        return Array(store.orderedByRecency(exercises)
            .filter { store.lastPerformedDates[$0.uuid] != nil }
            .prefix(maxCount))
    }

    @ViewBuilder
    private func showMoreRow(count: Int) -> some View {
        if count > 0 {
            Button("Show \(count.formatted()) More Exercises") { showingAllExercises = true }
                .foregroundStyle(LiteweightTheme.accent)
        }
    }

    @ViewBuilder
    private var activeFilterSection: some View {
        let section = Section {
            ExerciseActiveFilterChips(muscleGroup: $selectedMuscleGroup, equipment: $selectedEquipment)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        if #available(iOS 17, *) {
            section.listSectionSpacing(0)
        } else {
            section
        }
    }

    var body: some View {
        let listing = catalogSearch.listing(for: search, showingAll: showingAllExercises)
        let matches = listing.exercises
        let showsRecents = search.isEmpty && selectedMuscleGroup == nil && selectedEquipment == nil
            && !listing.recent.isEmpty
        let limitsBrowseRows = !hasExpandedBrowseList && !voiceOverEnabled && !UIAccessibility.isVoiceOverRunning
            && search.isEmpty && selectedMuscleGroup == nil && selectedEquipment == nil && !showingAllExercises
        let rowLimit = limitsBrowseRows ? min(40, matches.count) : matches.count
        let recentRows = listing.recentRows.prefix(rowLimit)
        let remainingRows = listing.remainingRows.prefix(max(0, rowLimit - recentRows.count))
        let hasDeferredRows = rowLimit < matches.count
        ExercisePickerNavigation {
            List {
                if selectedMuscleGroup != nil || selectedEquipment != nil {
                    activeFilterSection
                }
                if catalogSearch.catalog == nil {
                    EmptyView()
                } else if matches.isEmpty && catalogSearch.isSearching(search) {
                    ProgressView("Searching Exercises…")
                } else if matches.isEmpty {
                    emptyState
                } else if showsRecents {
                    Section("Recent") {
                        ForEach(recentRows) { row in
                            exerciseRow(row)
                        }
                    }

                    if !remainingRows.isEmpty || !hasDeferredRows {
                        Section("All Exercises") {
                            ForEach(remainingRows) { row in
                                exerciseRow(row)
                            }
                            if !hasDeferredRows {
                                showMoreRow(count: listing.moreCount)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(listing.rows.prefix(rowLimit)) { row in
                            exerciseRow(row)
                        }
                        if !hasDeferredRows {
                            showMoreRow(count: listing.moreCount)
                        }
                    } footer: {
                        if !hasDeferredRows {
                            Text("^[\(matches.count) exercise](inflect: true)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .modifier(ExercisePickerScrollEdge())
            .modifier(ExercisePickerListMargins())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // Pinned drawer, not the title row: in this sheet iOS hides Cancel and Add once search moves up.
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(ExerciseFilterText.searchPrompt(muscleGroup: selectedMuscleGroup,
                                                                     equipment: selectedEquipment)))
            .keepsToolbarWhileSearching()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: resetAndDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle, action: addSelectedExercises)
                        .fontWeight(.semibold)
                        .disabled(exerciseSelectorSelection.isEmpty)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    ExerciseFilterMenu(
                        muscleGroup: $selectedMuscleGroup,
                        equipment: $selectedEquipment,
                        muscleGroups: catalogSearch.catalog?.muscleGroups ?? [],
                        equipmentOptions: catalogSearch.catalog?.equipment ?? [])

                    Spacer()

                    Button {
                        showingCreateExercise = true
                    } label: {
                        Label("Create Exercise", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .onAppear { refreshCatalog() }
        .task {
            // Keep the full List update past the slide-in on every presentation,
            // including warm catalog opens. SwiftUI cancels this on dismissal.
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hasExpandedBrowseList = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            catalogSearch.expireCaptions()
            refreshCatalog()
        }
        .onReceive(exerciseStore.objectWillChange) { _ in
            // objectWillChange precedes storage. Queue the read itself instead of
            // debouncing a subscription SwiftUI can replace during that change.
            DispatchQueue.main.async { refreshCatalog() }
        }
        .onChange(of: [selectedMuscleGroup, selectedEquipment]) { _ in
            catalogSearch.applyFilters(muscleGroup: selectedMuscleGroup, equipment: selectedEquipment)
            if SettingsStore.shared.workoutHaptics {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .onChange(of: selectionFeedback) { _ in
            if SettingsStore.shared.workoutHaptics {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .task(id: catalogSearch.request(for: search)) {
            await catalogSearch.search(search)
        }
        .sheet(isPresented: $showingCreateExercise) {
            CreateCustomExerciseSheet(
                onDismiss: { showingCreateExercise = false }
            )
            .environmentObject(exerciseStore)
            .modifier(ExercisePickerSheetPresentation())
        }
        .sheet(item: $detailExercise) { exercise in
            ExercisePickerNavigation {
                ExerciseDetailView(exercise: exercise)
                    .liteweightScreen()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { detailExercise = nil }
                        }
                    }
            }
            .modifier(ExercisePickerSheetPresentation())
        }
        .sheet(item: $mediaExercise) { exercise in
            ExerciseMediaSheet(exercise: exercise)
        }
        .onChange(of: mediaFeedback) { _ in
            if SettingsStore.shared.workoutHaptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
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
                    Label("No matching exercises", systemImage: "line.3.horizontal.decrease")
                } description: {
                    Text("Try a different muscle group or equipment.")
                } actions: {
                    clearFiltersButton
                }
            }
        } else {
            VStack(spacing: 8) {
                if hasSearch {
                    Text("No results for \"\(search)\"").font(.headline)
                } else {
                    Label("No matching exercises", systemImage: "line.3.horizontal.decrease").font(.headline)
                    Text("Try a different muscle group or equipment.")
                        .font(.subheadline)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                    clearFiltersButton
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        }
    }

    private var clearFiltersButton: some View {
        Button("Clear Filters") {
            selectedMuscleGroup = nil
            selectedEquipment = nil
        }
    }

    @ViewBuilder
    private func exerciseRow(_ prepared: AddExerciseCatalog.Row) -> some View {
        let exercise = prepared.exercise
        let selectionNumber = exerciseSelectorSelection.firstIndex(of: exercise).map { $0 + 1 }
        let metadata = prepared.display

        let row = Button(action: { toggle(exercise) }) {
            HStack(spacing: 12) {
                selectionIndicator(number: selectionNumber)

                ExerciseDiagramThumbnail(exercise: exercise, size: 44)
                    .contentShape(Circle())
                    // A hold consumes the touch; only a short tap opens details.
                    // Movement cancels the hold so the List can scroll.
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
                            .exclusively(before: TapGesture())
                            .onEnded { result in
                                switch result {
                                case .first:
                                    guard metadata.hasPlayableDemonstration else { return }
                                    mediaExercise = exercise
                                    mediaFeedback += 1
                                case .second:
                                    detailExercise = exercise
                                }
                            }
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LiteweightTheme.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metadata.title)
                        .font(.subheadline)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metadata.accessibilityLabel)
        .accessibilityValue(selectionNumber.map {
            maximumSelectionCount == 1 ? "Selected" : "Selection \($0)"
        } ?? "Not selected")
        .accessibilityAction(named: Text("Show Details")) {
            detailExercise = exercise
        }

        if metadata.hasPlayableDemonstration {
            row.accessibilityAction(named: Text("Play Demonstration")) {
                mediaExercise = exercise
            }
        } else {
            row
        }
    }

    /// Ordered selection mirrors Photos; single-selection callers keep a check.
    private func selectionIndicator(number: Int?) -> some View {
        ZStack {
            if let number {
                Circle().fill(LiteweightTheme.accent)
                if maximumSelectionCount == 1 {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LiteweightTheme.onAccent)
                } else {
                    Text("\(number)")
                        .font(.liteweightMetric(.subheadline, weight: .semibold))
                        .foregroundStyle(LiteweightTheme.onAccent)
                }
            } else {
                Circle().strokeBorder(LiteweightTheme.outline, lineWidth: 2)
            }
        }
        .frame(width: selectionIndicatorSize, height: selectionIndicatorSize)
        .accessibilityHidden(true)
    }

    private func toggle(_ exercise: Exercise) {
        if let index = exerciseSelectorSelection.firstIndex(of: exercise) {
            exerciseSelectorSelection.remove(at: index)
        } else if maximumSelectionCount == 1 {
            exerciseSelectorSelection = [exercise]
        } else {
            exerciseSelectorSelection.append(exercise)
        }

        selectionFeedback += 1
    }

    private func addSelectedExercises() {
        guard !exerciseSelectorSelection.isEmpty else { return }
        onAdd(exerciseSelectorSelection)
        resetAndDismiss()
    }

    private var confirmationTitle: String {
        guard !exerciseSelectorSelection.isEmpty else { return actionTitle }
        return maximumSelectionCount == 1
            ? actionTitle
            : "\(actionTitle) \(exerciseSelectorSelection.count)"
    }
}

private struct ExercisePickerNavigation<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder var body: some View {
        if #available(iOS 16, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

private struct ExercisePickerScrollEdge: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // Translucent: rows soften under the pinned search instead of meeting a solid band.
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct ExercisePickerListMargins: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.contentMargins(.horizontal, 10, for: .scrollContent)
        } else {
            content
        }
    }
}

private struct ExercisePickerSheetPresentation: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.presentationDetents([.large]).presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

private extension View {
    /// Cancel and Add stay on screen while searching.
    @ViewBuilder func keepsToolbarWhileSearching() -> some View {
        if #available(iOS 17.1, *) {
            searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }
}

struct AddExercisesSheet_Previews: PreviewProvider {
    static var previews: some View {
//        Color.clear.sheet(isPresented: .constant(true)) {
        AddExercisesSheet(
            exercises: ExerciseStore.shared.shownExercises,
            recentExercises: [],
            onAdd: { _ in }
        )
        .environmentObject(ExerciseStore.shared)
//        }
    }
}
