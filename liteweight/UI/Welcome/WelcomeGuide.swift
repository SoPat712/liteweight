//
//  WelcomeGuide.swift
//  liteweight
//
//  Who sees the welcome, which pages they get, and the starter plans it can add.
//

import SwiftUI
import CoreData
import WorkoutDataKit

/// Main thread only, like the other app-wide stores.
final class WelcomeGuideController: ObservableObject {
    static let shared = WelcomeGuideController()
    static let completedVersionKey = "welcome.completedVersion"
    static let currentVersion = 1

    /// True until this person has finished or skipped the current welcome.
    static var isOutstanding: Bool {
        UserDefaults.standard.integer(forKey: completedVersionKey) < currentVersion
    }

    enum Mode: String, Identifiable {
        /// Every page: a new install, or Settings › Help › Welcome Guide.
        case full
        /// People who already have workouts: no unit or how-to-start pages.
        case returning
        var id: String { rawValue }
    }

    @Published var mode: Mode?
    /// Files picked on the how-to-start page. They open after the welcome closes,
    /// so the import progress and restore confirmation aren't hidden behind it.
    private var pendingHevyCSV: [Data] = []
    private var pendingBackup: Data?
    private var hasChecked = false

    private init() {}

    /// Screenshot runs, inspection screens, demos and the unit-test host.
    static var isSuppressed: Bool {
        let process = ProcessInfo.processInfo
        if process.environment["LITEWEIGHT_STANDALONE_TESTS"] != nil { return true }
        return process.arguments.contains { argument in
            argument == "-liteweightSkipWelcome"
                || argument == "-liteweightRunImportedDataSmokeCheck"
                || argument.hasPrefix("-liteweightInspect")
                || argument.hasPrefix("-liteweightSeed")
                || argument.hasPrefix("-liteweightDemo")
        }
    }

    /// Once per launch, from the root view.
    func presentIfNeeded(context: NSManagedObjectContext) {
        guard !hasChecked else { return }
        hasChecked = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-liteweightShowWelcome") {
            mode = .full
            LiteweightTips.setReady(false)
            return
        }
        #endif
        guard !Self.isSuppressed, Self.isOutstanding else {
            LiteweightTips.setReady(true)
            return
        }
        mode = Self.hasCompletedWorkout(in: context) ? .returning : .full
        LiteweightTips.setReady(false)
    }

    func replay() {
        mode = .full
        LiteweightTips.setReady(false)
    }

    func queueHevyImport(_ documents: [Data]) {
        pendingHevyCSV = documents
        pendingBackup = nil
    }

    func queueRestore(_ backup: Data) {
        pendingBackup = backup
        pendingHevyCSV = []
    }

    func finish() {
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.completedVersionKey)
        mode = nil
    }

    /// Runs after the cover has gone: tips may open, and picked files are handed to
    /// the same import and restore paths a file opened from Files uses.
    func didDismiss() {
        // Also called when an opening workout hides the welcome; it comes back after.
        guard mode == nil else { return }
        LiteweightTips.setReady(true)
        if !pendingHevyCSV.isEmpty {
            NotificationCenter.default.post(name: .ImportHevyCSV, object: self,
                                            userInfo: [importHevyCSVDataUserInfoKey: pendingHevyCSV])
        } else if let pendingBackup {
            NotificationCenter.default.post(name: .RestoreFromBackup, object: self,
                                            userInfo: [restoreFromBackupDataUserInfoKey: pendingBackup])
        }
        pendingHevyCSV = []
        pendingBackup = nil
    }

    private static func hasCompletedWorkout(in context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(booleanLiteral: true))
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }
}

// MARK: - Starter plans

/// Common splits with standard exercises, 3 sets of 8–12 (holds by time).
/// Exercises resolve through `catalogIDs`; one that doesn't resolve is skipped.
struct StarterPlan: Identifiable, Hashable {
    struct Day: Hashable {
        let title: String
        let exercises: [String]
    }

    let id: String
    let name: String
    let frequency: String
    let detail: String
    let days: [Day]

    static let all: [StarterPlan] = [
        StarterPlan(id: "fullBody", name: "Full Body", frequency: "3 days a week",
                    detail: "Workout A and B, alternating", days: [
                        Day(title: "Full Body A", exercises: [
                            "Squat: Barbell", "Bench Press: Barbell", "Row: Barbell (Bent Over)", "Plank",
                        ]),
                        Day(title: "Full Body B", exercises: [
                            "Deadlift: Barbell", "Overhead Press: Barbell", "Pulldown (Wide Grip)", "Lunges: Dumbbell",
                        ]),
                    ]),
        StarterPlan(id: "upperLower", name: "Upper / Lower", frequency: "4 days a week",
                    detail: "Upper and Lower, twice each", days: [
                        Day(title: "Upper", exercises: [
                            "Bench Press: Barbell", "Row: Barbell (Bent Over)", "Overhead Press: Barbell",
                            "Pulldown (Wide Grip)", "Biceps Curl: Dumbbell", "Triceps Pushdown: Cable (Rope)",
                        ]),
                        Day(title: "Lower", exercises: [
                            "Squat: Barbell", "Romanian Deadlift", "Leg Press", "Leg Curl (Lying)",
                            "Calf Raise: Machine (Standing)", "Plank",
                        ]),
                    ]),
        StarterPlan(id: "pushPullLegs", name: "Push / Pull / Legs", frequency: "3 or 6 days",
                    detail: "Push, Pull and Legs in turn", days: [
                        Day(title: "Push", exercises: [
                            "Bench Press: Barbell", "Overhead Press: Barbell", "Bench Press: Dumbbell (Incline)",
                            "Lateral Raise: Dumbbell", "Triceps Pushdown: Cable (Rope)",
                        ]),
                        Day(title: "Pull", exercises: [
                            "Deadlift: Barbell", "Pull Up", "Row: Cable (Seated)", "Face Pulls",
                            "Biceps Curl: Dumbbell (Hammer)",
                        ]),
                        Day(title: "Legs", exercises: [
                            "Squat: Barbell", "Romanian Deadlift", "Leg Press", "Leg Curl (Seated)",
                            "Calf Raise: Machine (Standing)",
                        ]),
                    ]),
    ]

    /// The colored muscle groups this plan trains, most exercises first.
    func muscleGroups(in catalog: [String: Exercise]) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for title in days.flatMap(\.exercises) {
            guard let group = catalog[title]?.muscleGroup, LiteweightPalette.hasMuscleColor(group) else { continue }
            if counts[group] == nil { order.append(group) }
            counts[group, default: 0] += 1
        }
        return order.enumerated()
            .sorted { (counts[$0.element] ?? 0, -$0.offset) > (counts[$1.element] ?? 0, -$1.offset) }
            .map(\.element)
    }

    /// Plans name exercises by their catalog source title, resolved through stable IDs:
    /// the store shows display titles, which can differ from these.
    private static let catalogIDs: [String: String] = [
        "Squat: Barbell": "2339F5BD-2E8C-4446-B1A5-6156B1192229",
        "Bench Press: Barbell": "C0D3C3CD-9F1F-4A89-B845-DAB5923B22A7",
        "Row: Barbell (Bent Over)": "6EB5B9C9-C953-459E-AFDE-2D31B1BEFAE0",
        "Plank": "82008701-4189-4693-9B68-00E32C78AB92",
        "Deadlift: Barbell": "E301F9A9-9516-47E3-9E77-D2C7E50B4D7A",
        "Overhead Press: Barbell": "3D405857-F1A8-4F85-858C-231F0CEF653A",
        "Pulldown (Wide Grip)": "91F466BA-1D91-459A-8C5B-81E0B46C54AC",
        "Lunges: Dumbbell": "D3BE22C1-9276-4EF9-9888-2E98D76DC618",
        "Biceps Curl: Dumbbell": "154B1CB5-38B3-426D-B729-FF92A53D22A4",
        "Triceps Pushdown: Cable (Rope)": "FDEC211B-2157-4232-8E25-F796F067D37D",
        "Romanian Deadlift": "37DF9EB1-8E5F-404E-91B2-36210D356F95",
        "Leg Press": "8B3DE466-1552-4978-A378-55F64E8CA66B",
        "Leg Curl (Lying)": "25B6655E-895A-41CB-835A-247A3A7B2E0F",
        "Calf Raise: Machine (Standing)": "4A5CE1F5-EF10-436C-8ACB-1D6D5928AEC3",
        "Bench Press: Dumbbell (Incline)": "C04B1262-EF69-449E-963F-282D34A0AA8D",
        "Lateral Raise: Dumbbell": "92D5B230-A226-45DD-8AA1-D3271EC24AF8",
        "Pull Up": "59185216-6167-4427-AC10-38A3FDA17572",
        "Row: Cable (Seated)": "C30BC020-CD01-4DC6-BACD-BAB8C88D208F",
        "Face Pulls": "C4035736-EAF3-4DAD-8B74-BD1537E6B72D",
        "Biceps Curl: Dumbbell (Hammer)": "1A3DFD15-984D-4EDE-BD34-B4DA7129B9B6",
        "Leg Curl (Seated)": "8CD1F963-7570-467A-A15E-FAAFFEBF2546",
    ]

    /// Source title → the store's exercise (with its display title).
    static func catalogByTitle(_ store: ExerciseStore) -> [String: Exercise] {
        catalogIDs.reduce(into: [:]) { result, entry in
            if let id = UUID(uuidString: entry.value), let exercise = store.find(with: id) { result[entry.key] = exercise }
        }
    }

    /// Adds one saved workout per day to the first saved-workout folder, in one save.
    func install(into context: NSManagedObjectContext, exerciseStore: ExerciseStore) throws {
        let catalog = Self.catalogByTitle(exerciseStore)
        try context.persistMutation(save: { try context.save() }) {
            let request: NSFetchRequest<WorkoutPlan> = WorkoutPlan.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutPlan.title, ascending: true)]
            request.fetchLimit = 1
            let container = try context.fetch(request).first ?? WorkoutPlan.create(context: context)
            for day in days {
                let routine = WorkoutRoutine.create(context: context)
                routine.workoutPlan = container
                routine.title = day.title
                let exercises = day.exercises.compactMap { catalog[$0] }.map { exercise -> WorkoutRoutineExercise in
                    let item = WorkoutRoutineExercise.create(context: context)
                    item.exerciseUuid = exercise.uuid
                    let type = SetTrackingType.defaultType(name: exercise.title, equipment: exercise.equipment,
                                                           category: exercise.muscleGroup)
                    let sets = (0..<3).map { _ -> WorkoutRoutineSet in
                        let set = WorkoutRoutineSet.create(context: context)
                        if type.usesDuration && !type.usesReps {
                            set.durationValue = 45
                        } else {
                            set.minRepetitionsValue = 8
                            set.maxRepetitionsValue = 12
                        }
                        return set
                    }
                    item.workoutRoutineSets = NSOrderedSet(array: sets)
                    return item
                }
                routine.workoutRoutineExercises = NSOrderedSet(array: exercises)
            }
        }
    }
}
