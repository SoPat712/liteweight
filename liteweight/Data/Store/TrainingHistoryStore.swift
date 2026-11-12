import Combine
import CoreData
import Foundation
import WorkoutDataKit

/// Immutable dashboard values. Managed objects stay on their context's queue;
/// screens only resolve an object ID when opening a workout.
struct TrainingExerciseSnapshot {
    let id: NSManagedObjectID
    let uuid: UUID?
    let setCount: Int
    let repetitions: Int
    let volume: Double
}

struct TrainingSessionSnapshot: Identifiable {
    let id: NSManagedObjectID
    let date: Date
    let title: String?
    let displayTitle: String
    let duration: TimeInterval
    let setCount: Int
    let repetitions: Int
    let volume: Double
    let effort: Double?
    let exercises: [TrainingExerciseSnapshot]
}

struct TrainingExerciseTotals {
    var sessions: Int = 0
    var sets: Int = 0
    var lastTrained: Date = .distantPast
}

struct TrainingHistorySnapshot {
    var sessions: [TrainingSessionSnapshot] = []
    var byDay: [Date: [TrainingSessionSnapshot]] = [:]
    var trainedWeeks: Set<Date> = []
    var exerciseTotals: [UUID: TrainingExerciseTotals] = [:]
    var recordSetIDs: Set<NSManagedObjectID> = []
    var recordCounts: [NSManagedObjectID: Int] = [:]
    var exerciseBests: [UUID: ExerciseBests] = [:]
    var recordEvents: [ExerciseBests.RecordEvent] = []
    var lastRoutineCompletion: [NSManagedObjectID: Date] = [:]

    func streak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        var count = 0
        for offset in 0..<520 {
            if trainedWeeks.contains(week) { count += 1 }
            else if offset > 0 { break }
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return count
    }

    /// Rebuilds the per-day, per-week and per-exercise indexes from `sessions`,
    /// the same way `build` fills them. Used when sessions come from the cache.
    mutating func indexSessions(calendar: Calendar = .current) {
        byDay = [:]
        trainedWeeks = []
        exerciseTotals = [:]
        for session in sessions {
            if let week = calendar.dateInterval(of: .weekOfYear, for: session.date) { trainedWeeks.insert(week.start) }
            byDay[calendar.startOfDay(for: session.date), default: []].append(session)
            for (uuid, entries) in Dictionary(grouping: session.exercises.compactMap { entry in entry.uuid.map { ($0, entry) } }, by: { $0.0 }) {
                var total = exerciseTotals[uuid, default: TrainingExerciseTotals()]
                total.sessions += 1
                total.sets += entries.reduce(0) { $0 + $1.1.setCount }
                total.lastTrained = max(total.lastTrained, session.date)
                exerciseTotals[uuid] = total
            }
        }
    }

    static func build(from workouts: [Workout], calendar: Calendar = .current,
                      catalog: [UUID: Exercise] = [:],
                      titleExercises: [Exercise]? = nil) -> Self {
        var result = Self()
        let displayTitleExercises = titleExercises ?? Array(catalog.values)
        var bestsSets: [ExerciseBests.SetResult] = []
        var completedSetIDs: [NSManagedObjectID: [NSManagedObjectID]] = [:]
        for workout in workouts where !workout.isCurrentWorkout {
            let exercises = (workout.workoutExercises?.array as? [WorkoutExercise] ?? []).compactMap { exercise -> TrainingExerciseSnapshot? in
                let sets = (exercise.workoutSets?.array as? [WorkoutSet] ?? []).filter(\.isCompleted)
                guard !sets.isEmpty else { return nil }
                completedSetIDs[workout.objectID, default: []].append(contentsOf: sets.map(\.objectID))
                let preferred = exercise.trackingType(catalogExercise: exercise.exerciseUuid.flatMap { catalog[$0] })
                if let uuid = exercise.exerciseUuid, let date = workout.start {
                    bestsSets += sets.map { set in
                        ExerciseBests.SetResult(
                            id: set.objectID, exerciseID: uuid, workoutID: workout.objectID, date: date,
                            weight: set.weightValue, repetitions: Int(set.repetitionsValue),
                            trackingType: SetTrackingType.resolved(preferred, from: set.trackingData),
                            duration: set.durationValue, distance: set.distanceValue,
                            isCompleted: set.isCompleted, isWarmUp: set.tagValue == .warmUp
                        )
                    }
                }
                let volume = sets.reduce(0.0) { sum, set in
                    let type = SetTrackingType.resolved(preferred, from: set.trackingData)
                    return sum + type.volume(weight: set.weightValue, reps: Int(set.repetitionsValue))
                }
                return TrainingExerciseSnapshot(id: exercise.objectID, uuid: exercise.exerciseUuid,
                    setCount: sets.count, repetitions: sets.reduce(0) { $0 + Int($1.repetitionsValue) }, volume: volume)
            }
            guard !exercises.isEmpty else { continue }
            let date = workout.start ?? .distantPast
            if let routine = workout.workoutRoutine {
                result.lastRoutineCompletion[routine.objectID] = max(result.lastRoutineCompletion[routine.objectID] ?? .distantPast, date)
            }
            let session = TrainingSessionSnapshot(id: workout.objectID, date: date, title: workout.title,
                displayTitle: workout.displayTitle(in: displayTitleExercises),
                duration: max(0, workout.duration ?? 0), setCount: exercises.reduce(0) { $0 + $1.setCount },
                repetitions: exercises.reduce(0) { $0 + $1.repetitions }, volume: exercises.reduce(0) { $0 + $1.volume },
                effort: workout.sessionEffortValue, exercises: exercises)
            result.sessions.append(session)
            if let week = calendar.dateInterval(of: .weekOfYear, for: date) { result.trainedWeeks.insert(week.start) }
            result.byDay[calendar.startOfDay(for: date), default: []].append(session)
            // Count a workout once even if the same exercise appears twice.
            for (uuid, entries) in Dictionary(grouping: exercises.compactMap { entry in entry.uuid.map { ($0, entry) } }, by: { $0.0 }) {
                var total = result.exerciseTotals[uuid, default: TrainingExerciseTotals()]
                total.sessions += 1
                total.sets += entries.reduce(0) { $0 + $1.1.setCount }
                total.lastTrained = max(total.lastTrained, date)
                result.exerciseTotals[uuid] = total
            }
        }
        result.sessions.sort { $0.date > $1.date }
        result.recordSetIDs = TrainingRecordIndex.recordSetIDs(in: workouts.filter { !$0.isCurrentWorkout })
        result.recordCounts = completedSetIDs.mapValues { ids in
            ids.filter { result.recordSetIDs.contains($0) }.count
        }
        result.exerciseBests = Dictionary(grouping: bestsSets, by: \.exerciseID).mapValues { ExerciseBests(sets: $0) }
        result.recordEvents = ExerciseBests.recordEvents(in: bestsSets, historyRecordSetIDs: result.recordSetIDs)
        return result
    }
}

/// One debounced background history read shared by Home, History and day recaps.
/// No history traversal, Core Data faulting or catalog search runs from a view body.
@MainActor final class TrainingHistoryStore: ObservableObject {
    static let shared = TrainingHistoryStore()
    @Published private(set) var snapshot = TrainingHistorySnapshot()
    /// False until the first history read finishes; the empty snapshot before it isn't "no history".
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var context: NSManagedObjectContext?
    private var observers: Set<AnyCancellable> = []
    private var refreshPending = false

    /// Shows the last saved read at once; the first refresh then replaces it.
    /// A small cache loads before the first frame, a large one off the main thread.
    init() {
        guard let url = TrainingHistoryCache.fileURL,
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return }
        let reader = WorkoutDataStorage.shared.persistentContainer.newBackgroundContext()
        if size <= TrainingHistoryCache.synchronousLoadLimit {
            if let restored = reader.performAndWait({ TrainingHistoryCache.load(from: url, in: reader) }) {
                snapshot = restored
                hasLoaded = true
            }
        } else {
            Task {
                let restored = await reader.perform { TrainingHistoryCache.load(from: url, in: reader) }
                // A full read that finished first is newer; never replace it.
                guard let restored, !self.hasLoaded else { return }
                self.snapshot = restored
                self.hasLoaded = true
            }
        }
    }

    func observe(in source: NSManagedObjectContext) {
        guard let coordinator = source.persistentStoreCoordinator,
              context?.persistentStoreCoordinator !== coordinator else { return }
        let reader = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        reader.persistentStoreCoordinator = coordinator
        reader.undoManager = nil
        context = reader
        observers.removeAll()
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { notification in
                guard (notification.object as? NSManagedObjectContext)?.persistentStoreCoordinator === coordinator else { return false }
                let entities: Set<String> = ["Workout", "WorkoutExercise", "WorkoutSet"]
                return [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
                    (notification.userInfo?[key] as? Set<NSManagedObject>)?.contains { entities.contains($0.entity.name ?? "") } ?? false
                }
            }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &observers)
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &observers)
        // Peer merges save silently, so observe the persisted value as well as
        // local edits. Ignore unrelated defaults writes to avoid history rescans.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .merge(with: NotificationCenter.default.publisher(for: SetTrackingPreferences.didChangeNotification, object: UserDefaults.standard))
            .map { _ in UserDefaults.standard.data(forKey: SetTrackingPreferences.storageKey) }
            .prepend(UserDefaults.standard.data(forKey: SetTrackingPreferences.storageKey))
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &observers)
        refresh()
    }

    func refresh() {
        guard let context else { return }
        guard !isLoading else { refreshPending = true; return }
        isLoading = true
        // Capture the catalog on the main actor; the background context must
        // not read the observable exercise store while it is being updated.
        let catalog = ExerciseStore.shared.exercisesByUUID
        let titleExercises = ExerciseStore.shared.exercises
        Task {
            do {
                let value = try await context.perform {
                    defer { context.reset() }
                    let request = Workout.fetchRequest()
                    request.predicate = NSPredicate(format: "isCurrentWorkout != YES")
                    request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: false)]
                    request.relationshipKeyPathsForPrefetching = ["workoutExercises", "workoutExercises.workoutSets"]
                    return TrainingHistorySnapshot.build(from: try context.fetch(request), catalog: catalog,
                                                         titleExercises: titleExercises)
                }
                snapshot = value
                error = nil
                // Encode and write after publishing, so the cache never delays the screens.
                TrainingHistoryCache.saveInBackground(value)
            } catch { self.error = error.localizedDescription }
            if !hasLoaded { hasLoaded = true }
            isLoading = false
            if refreshPending { refreshPending = false; refresh() }
        }
    }
}

/// The last history read, saved so Home, History and the Workout tab show real
/// numbers at cold launch. Object IDs are stored as URI tails ("p12") under one
/// store prefix. A cache naming any workout the store no longer has (deleted just
/// before quitting, or replaced by a restore) is ignored, because screens open
/// those IDs directly. Exercise bests aren't cached; the first refresh fills them.
/// About 0.4 KB per workout (six exercises), so ~650 workouts load synchronously.
enum TrainingHistoryCache {
    static let version = 2
    static let synchronousLoadLimit = 256 * 1024
    /// Home's records card only reads the last 30 days.
    private static let recordWindow: TimeInterval = 45 * 24 * 3600

    static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("liteweight", isDirectory: true)
            .appendingPathComponent("training-history-cache.json", isDirectory: false)
    }

    private struct Payload: Codable {
        var version: Int
        var store: String
        var exerciseIDs: [UUID]
        var sessions: [Session]
        var routines: [String: Date]
        var recordSetIDs: [String]
        var records: [Record]
    }

    private struct Session: Codable {
        var id: String
        var date: Date
        var title: String?
        var name: String
        var duration: TimeInterval
        var sets: Int
        var reps: Int
        var volume: Double
        var effort: Double?
        var exercises: [Exercise]
        var recordCount: Int
        enum CodingKeys: String, CodingKey {
            case id = "i", date = "d", title = "t", name = "n", duration = "u"
            case sets = "s", reps = "r", volume = "v", effort = "e", exercises = "x"
            case recordCount = "k"
        }
    }

    private struct Exercise: Codable {
        var id: String
        var exercise: Int?
        var sets: Int
        var reps: Int
        var volume: Double
        enum CodingKeys: String, CodingKey {
            case id = "i", exercise = "u", sets = "s", reps = "r", volume = "v"
        }
    }

    private struct Record: Codable {
        var set: String
        var workout: String
        var exercise: Int
        var date: Date
        var weight: Double
        var reps: Int
        var type: SetTrackingType
        var duration: TimeInterval?
        var distance: Double?
        var kind: Int
    }

    private enum Entity {
        static let workout = "Workout/"
        static let exercise = "WorkoutExercise/"
        static let set = "WorkoutSet/"
        static let routine = "WorkoutRoutine/"
    }

    // MARK: Encoding

    static func encode(_ snapshot: TrainingHistorySnapshot, now: Date = Date()) -> Data? {
        guard let first = snapshot.sessions.first?.id ?? snapshot.lastRoutineCompletion.keys.first,
              let host = first.uriRepresentation().host else {
            return try? JSONEncoder().encode(Payload(version: version, store: "", exerciseIDs: [], sessions: [],
                                                     routines: [:], recordSetIDs: [], records: []))
        }
        let store = "x-coredata://" + host + "/"
        func tail(_ id: NSManagedObjectID, _ entity: String) -> String? {
            guard !id.isTemporaryID else { return nil }
            let uri = id.uriRepresentation().absoluteString
            guard uri.hasPrefix(store + entity) else { return nil }
            return String(uri.dropFirst(store.count + entity.count))
        }
        var exerciseIDs: [UUID] = []
        var exerciseIndex: [UUID: Int] = [:]
        func index(_ uuid: UUID) -> Int {
            if let existing = exerciseIndex[uuid] { return existing }
            exerciseIDs.append(uuid)
            exerciseIndex[uuid] = exerciseIDs.count - 1
            return exerciseIDs.count - 1
        }

        var sessions: [Session] = []
        sessions.reserveCapacity(snapshot.sessions.count)
        for session in snapshot.sessions {
            guard let id = tail(session.id, Entity.workout) else { return nil }
            var exercises: [Exercise] = []
            for entry in session.exercises {
                guard let entryID = tail(entry.id, Entity.exercise) else { return nil }
                exercises.append(Exercise(id: entryID, exercise: entry.uuid.map(index), sets: entry.setCount,
                                          reps: entry.repetitions, volume: entry.volume))
            }
            sessions.append(Session(id: id, date: session.date, title: session.title, name: session.displayTitle,
                                    duration: session.duration, sets: session.setCount, reps: session.repetitions,
                                    volume: session.volume, effort: session.effort, exercises: exercises,
                                    recordCount: snapshot.recordCounts[session.id] ?? 0))
        }
        var routines: [String: Date] = [:]
        for (id, date) in snapshot.lastRoutineCompletion {
            guard let key = tail(id, Entity.routine) else { return nil }
            routines[key] = date
        }
        var recordSetIDs: [String] = []
        for id in snapshot.recordSetIDs {
            guard let key = tail(id, Entity.set) else { return nil }
            recordSetIDs.append(key)
        }
        var records: [Record] = []
        for event in snapshot.recordEvents where event.date >= now.addingTimeInterval(-recordWindow) {
            let result = event.result
            guard let set = tail(result.id, Entity.set), let workout = tail(result.workoutID, Entity.workout) else { return nil }
            let kind: Int
            switch event.kind {
            case .heaviest: kind = 0
            case .estimatedOneRepMax: kind = 1
            case .set: kind = 2
            }
            records.append(Record(set: set, workout: workout, exercise: index(result.exerciseID), date: result.date,
                                  weight: result.weight, reps: result.repetitions, type: result.trackingType,
                                  duration: result.duration, distance: result.distance, kind: kind))
        }
        return try? JSONEncoder().encode(Payload(version: version, store: store, exerciseIDs: exerciseIDs,
                                                 sessions: sessions, routines: routines,
                                                 recordSetIDs: recordSetIDs, records: records))
    }

    /// Call on `context`'s queue. Returns nil, and never a partial history, when
    /// the file is from another version, another store, or names a missing workout.
    static func decode(_ data: Data, in context: NSManagedObjectContext,
                       calendar: Calendar = .current) -> TrainingHistorySnapshot? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version else { return nil }
        var snapshot = TrainingHistorySnapshot()
        guard !payload.sessions.isEmpty || !payload.routines.isEmpty else { return snapshot }
        guard let coordinator = context.persistentStoreCoordinator else { return nil }
        func resolve(_ tail: String, _ entity: String) -> NSManagedObjectID? {
            URL(string: payload.store + entity + tail).flatMap { coordinator.managedObjectID(forURIRepresentation: $0) }
        }
        func exerciseID(_ index: Int) -> UUID? {
            payload.exerciseIDs.indices.contains(index) ? payload.exerciseIDs[index] : nil
        }

        let request = NSFetchRequest<NSManagedObjectID>(entityName: "Workout")
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "isCurrentWorkout != YES")
        guard let existing = try? Set(context.fetch(request)) else { return nil }

        var sessions: [TrainingSessionSnapshot] = []
        sessions.reserveCapacity(payload.sessions.count)
        for session in payload.sessions {
            guard let id = resolve(session.id, Entity.workout), existing.contains(id) else { return nil }
            snapshot.recordCounts[id] = session.recordCount
            var exercises: [TrainingExerciseSnapshot] = []
            for entry in session.exercises {
                guard let entryID = resolve(entry.id, Entity.exercise) else { return nil }
                exercises.append(TrainingExerciseSnapshot(id: entryID, uuid: entry.exercise.flatMap(exerciseID),
                                                          setCount: entry.sets, repetitions: entry.reps, volume: entry.volume))
            }
            sessions.append(TrainingSessionSnapshot(id: id, date: session.date, title: session.title,
                                                    displayTitle: session.name, duration: session.duration,
                                                    setCount: session.sets, repetitions: session.reps,
                                                    volume: session.volume, effort: session.effort, exercises: exercises))
        }
        snapshot.sessions = sessions
        snapshot.indexSessions(calendar: calendar)
        for (key, date) in payload.routines {
            guard let id = resolve(key, Entity.routine) else { return nil }
            snapshot.lastRoutineCompletion[id] = date
        }
        snapshot.recordSetIDs = Set(payload.recordSetIDs.compactMap { resolve($0, Entity.set) })
        for record in payload.records {
            guard let set = resolve(record.set, Entity.set), let workout = resolve(record.workout, Entity.workout),
                  existing.contains(workout), let exercise = exerciseID(record.exercise) else { return nil }
            let kind: ExerciseBests.RecordEvent.Kind = record.kind == 0 ? .heaviest : record.kind == 1 ? .estimatedOneRepMax : .set
            let result = ExerciseBests.SetResult(id: set, exerciseID: exercise, workoutID: workout, date: record.date,
                                                 weight: record.weight, repetitions: record.reps, trackingType: record.type,
                                                 duration: record.duration, distance: record.distance)
            snapshot.recordEvents.append(ExerciseBests.RecordEvent(result: result, kind: kind))
        }
        return snapshot
    }

    // MARK: File

    /// Serial, so an older read can never overwrite a newer one.
    private static let writeQueue = DispatchQueue(label: "liteweight.trainingHistoryCache", qos: .utility)

    static func saveInBackground(_ snapshot: TrainingHistorySnapshot) {
        writeQueue.async { save(snapshot) }
    }

    static func save(_ snapshot: TrainingHistorySnapshot) {
        guard var url = fileURL else { return }
        guard let data = encode(snapshot) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Call on `context`'s queue. Removes a file it can't use.
    static func load(from url: URL, in context: NSManagedObjectContext) -> TrainingHistorySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = decode(data, in: context) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return snapshot
    }
}

/// Pareto comparisons for lifting records; scalar metrics use the first value
/// with a zero second value so reps, meters and seconds never mix dimensions.
private struct TrainingRecordFrontier {
    private var pairs: [SetTrackingType.PersonalRecordMeasurement] = []

    func dominates(_ value: SetTrackingType.PersonalRecordMeasurement) -> Bool {
        pairs.contains { $0.dominates(value) }
    }

    mutating func insert(_ value: SetTrackingType.PersonalRecordMeasurement) {
        guard !dominates(value) else { return }
        pairs.removeAll { value.dominates($0) }
        pairs.append(value)
    }
}

private enum TrainingRecordIndex {
    private static func measurement(for set: WorkoutSet, preferred: SetTrackingType) -> (key: String, value: SetTrackingType.PersonalRecordMeasurement)? {
        let data = set.trackingData
        let type = SetTrackingType.resolved(preferred, from: data)
        if type.usesWeight, set.weight == nil { return nil }
        if type.usesReps, set.repetitions == nil { return nil }
        guard let value = type.personalRecordMeasurement(from: data) else { return nil }
        return (type.rawValue, value)
    }

    static func recordSetIDs(in workouts: [Workout]) -> Set<NSManagedObjectID> {
        var records: Set<NSManagedObjectID> = []
        var trained: Set<String> = []
        var previous: [String: TrainingRecordFrontier] = [:]
        let dated = Dictionary(grouping: workouts.filter { $0.start != nil }, by: { $0.start! })
        // The model resolves every row using its UUID override (or weight/reps),
        // independent of catalog metadata and other rows in this exercise.
        let overrides = SetTrackingPreferences.load().overrides

        // Workouts sharing a start are peers, never each other's prior history.
        for date in dated.keys.sorted() {
            let batch = dated[date] ?? []
            for workout in batch {
                for exercise in workout.workoutExercises?.array as? [WorkoutExercise] ?? [] {
                    guard let uuid = exercise.exerciseUuid else { continue }
                    let preferred = overrides[uuid.uuidString]?.type ?? .weightReps
                    var earlier: [String: TrainingRecordFrontier] = [:]
                    for set in exercise.workoutSets?.array as? [WorkoutSet] ?? [] {
                        guard let metric = measurement(for: set, preferred: preferred) else { continue }
                        let key = uuid.uuidString + ":" + metric.key
                        if set.isCompleted, trained.contains(key),
                           !(previous[key]?.dominates(metric.value) ?? false),
                           !(earlier[key]?.dominates(metric.value) ?? false) {
                            records.insert(set.objectID)
                        }
                        earlier[key, default: TrainingRecordFrontier()].insert(metric.value)
                    }
                }
            }
            for workout in batch {
                for exercise in workout.workoutExercises?.array as? [WorkoutExercise] ?? [] {
                    guard let uuid = exercise.exerciseUuid else { continue }
                    let preferred = overrides[uuid.uuidString]?.type ?? .weightReps
                    for set in exercise.workoutSets?.array as? [WorkoutSet] ?? [] where set.isCompleted {
                        guard let metric = measurement(for: set, preferred: preferred) else { continue }
                        let key = uuid.uuidString + ":" + metric.key
                        trained.insert(key)
                        previous[key, default: TrainingRecordFrontier()].insert(metric.value)
                    }
                }
            }
        }
        return records
    }
}
