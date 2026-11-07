import CoreData
import Foundation
import WorkoutDataKit

/// Validated changes only. The caller owns one persistMutation/save boundary,
/// so a failed save can undo the complete arrangement without touching sets.
enum WorkoutOrganization {
    enum Failure: LocalizedError {
        case inactiveWorkout
        case changedWorkout
        case noPartner

        var errorDescription: String? {
            switch self {
            case .inactiveWorkout: return "This workout is no longer active."
            case .changedWorkout: return "The exercise list changed. Close this sheet and open it again."
            case .noPartner: return "Choose at least one other exercise for the superset."
            }
        }
    }

    static func setSuperset(
        in workout: Workout,
        source: WorkoutExercise,
        partnerIDs: Set<NSManagedObjectID>
    ) throws {
        let exercises = try activeExercises(in: workout)
        let ids = Set(exercises.map(\.objectID))
        guard ids.contains(source.objectID), source.workout == workout,
              source.managedObjectContext === workout.managedObjectContext,
              !partnerIDs.contains(source.objectID), partnerIDs.isSubset(of: ids) else {
            throw Failure.changedWorkout
        }
        guard !partnerIDs.isEmpty else { throw Failure.noPartner }

        let sourceGroup = source.supersetUuid
        var members = partnerIDs.union([source.objectID])
        // Selecting another existing group always keeps that whole group linked.
        for candidate in exercises where partnerIDs.contains(candidate.objectID) {
            if let group = candidate.supersetUuid, group != sourceGroup {
                members.formUnion(exercises.filter { $0.supersetUuid == group }.map(\.objectID))
            }
        }

        let selected = exercises.filter { members.contains($0.objectID) }
        let previousGroups = Set(selected.compactMap(\.supersetUuid))
        let reusableGroup = selected.compactMap(\.supersetUuid).first { group in
            let groupMembers = Set(exercises.filter { $0.supersetUuid == group }.map(\.objectID))
            return groupMembers.isSubset(of: members)
        }
        let group = reusableGroup ?? UUID()
        selected.forEach { $0.supersetUuid = group }

        // Unselected members retain their old group if two or more remain.
        // A single remaining member must not keep an orphan Superset badge.
        for previousGroup in previousGroups where previousGroup != group {
            let remaining = exercises.filter { $0.supersetUuid == previousGroup }
            if remaining.count < 2 { remaining.forEach { $0.supersetUuid = nil } }
        }
    }

    static func reorder(
        _ orderedIDs: [NSManagedObjectID],
        in workout: Workout
    ) throws {
        let exercises = try activeExercises(in: workout)
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.objectID, $0) })
        guard orderedIDs.count == exercises.count,
              Set(orderedIDs).count == orderedIDs.count,
              Set(orderedIDs) == Set(byID.keys) else { throw Failure.changedWorkout }
        workout.workoutExercises = NSOrderedSet(array: orderedIDs.compactMap { byID[$0] })
    }

    private static func activeExercises(in workout: Workout) throws -> [WorkoutExercise] {
        guard workout.isCurrentWorkout, !workout.isDeleted,
              workout.managedObjectContext != nil else { throw Failure.inactiveWorkout }
        return (workout.workoutExercises?.array as? [WorkoutExercise] ?? []).filter { !$0.isDeleted }
    }
}
