//
//  WorkoutDataStorage.swift
//  WorkoutDataKit
//
//  Created by Karim Abou Zeid on 05.12.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import CoreData
import Combine
import os.log

public class WorkoutDataStorage {
    // make sure the model is only ever loaded once to avoid "Multiple NSEntityDescriptions Claim NSManagedObject Subclass" errors
    public static var model: NSManagedObjectModel = {
        // TODO: try to use NSManagedObjectModel.mergedModel(from: [Bundle(for: Self.self))
        guard let modelURL = Bundle(for: WorkoutDataStorage.self).url(forResource: "WorkoutData", withExtension: "momd") else { fatalError("invalid WorkoutData model URL") }
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else { fatalError("could not create managed object model from \(modelURL)") }
        return model
    }()
    
    public let persistentContainer: NSPersistentContainer
    
    private var workoutDataObserverCancellable: Cancellable?
    
    public init(storeDescription: NSPersistentStoreDescription? = nil) {
        // create the core data stack
        persistentContainer = NSPersistentContainer(name: "WorkoutData", managedObjectModel: Self.model)
        if let storeDescription = storeDescription {
            assert(storeDescription.shouldAddStoreAsynchronously == false) // this is the default value
            persistentContainer.persistentStoreDescriptions = [storeDescription]
        }

        if let description = persistentContainer.persistentStoreDescriptions.first,
           description.type == NSSQLiteStoreType,
           let storeURL = description.url {
            do {
                try Self.migrateStoreIfNeeded(at: storeURL)
            } catch {
                os_log(
                    "Staged store migration failed; Core Data will attempt its configured fallback: %{public}@",
                    log: .migration,
                    type: .error,
                    error.localizedDescription
                )
            }
        }

        os_log("Loading persistent store", log: .workoutDataStorage, type: .default)
        loadPersistentStores(tryToRecoverFromFailedMigration: true) { storeDescription in
            os_log("Successfully loaded persistent store: %@", log: .workoutDataStorage, type: .info, storeDescription)
        }
    }
    
    private func loadPersistentStores(tryToRecoverFromFailedMigration: Bool, completion: @escaping (NSPersistentStoreDescription) -> Void) {
        persistentContainer.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                 
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                os_log("Could not load persistent store", log: .workoutDataStorage, type: .fault, error)
                guard tryToRecoverFromFailedMigration && error.code == NSMigrationError else {
                    fatalError("Could not load persistent store \(storeDescription): \(error.localizedDescription)")
                }
                os_log("Trying to recover from migration error", log: .workoutDataStorage, type: .default)
                self.loadPersistentStores(tryToRecoverFromFailedMigration: false) { storeDescription in
                    Self.tryToRecoverFromMigrationError(context: self.persistentContainer.viewContext)
                    completion(storeDescription)
                }
            } else {
                completion(storeDescription)
            }
        })
    }
}

extension WorkoutDataStorage {
    private struct VersionedModel {
        let version: Int
        let model: NSManagedObjectModel
    }

    enum StagedMigrationError: LocalizedError {
        case modelBundleMissing
        case modelMissing(String)
        case sourceModelUnknown
        case mappingMissing(Int, Int)

        var errorDescription: String? {
            switch self {
            case .modelBundleMissing:
                return "The bundled WorkoutData model could not be found."
            case .modelMissing(let name):
                return "The bundled WorkoutData model version \(name) could not be loaded."
            case .sourceModelUnknown:
                return "The workout database uses an unsupported model version."
            case .mappingMissing(let source, let destination):
                return "No safe mapping exists from WorkoutData v\(source) to v\(destination)."
            }
        }
    }

    /// Migrates old stores in deliberate stages. Versions 1–3 first use the
    /// bundled custom mappings to v4 (which generate UUIDs and translate legacy
    /// exercise identifiers), then v4→v5→v6 use inferred lightweight mappings
    /// for the additive schema changes.
    static func migrateStoreIfNeeded(at storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
        guard !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { return }

        let versions = try bundledModels()
        guard let source = versions.first(where: {
            $0.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        }) else {
            throw StagedMigrationError.sourceModelUnknown
        }
        guard let version4 = versions.first(where: { $0.version == 4 }),
              let version5 = versions.first(where: { $0.version == 5 }),
              let version6 = versions.first(where: { $0.version == 6 }) else {
            throw StagedMigrationError.modelBundleMissing
        }

        let fileManager = FileManager.default
        let migrationDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent(".liteweight-migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: migrationDirectory) }

        var workingURL = storeURL
        var workingModel = source.model

        if source.version < 4 {
            guard let mapping = NSMappingModel(
                from: [Bundle(for: WorkoutDataStorage.self)],
                forSourceModel: source.model,
                destinationModel: version4.model
            ) else {
                throw StagedMigrationError.mappingMissing(source.version, 4)
            }

            let destinationURL = migrationDirectory.appendingPathComponent("WorkoutData-v4.sqlite")
            try migrateStore(
                from: workingURL,
                sourceModel: workingModel,
                to: destinationURL,
                destinationModel: version4.model,
                mapping: mapping
            )
            workingURL = destinationURL
            workingModel = version4.model
        }

        if source.version < 5 {
            let mapping: NSMappingModel
            do {
                mapping = try NSMappingModel.inferredMappingModel(
                    forSourceModel: workingModel,
                    destinationModel: version5.model
                )
            } catch {
                throw StagedMigrationError.mappingMissing(4, 5)
            }

            let destinationURL = migrationDirectory.appendingPathComponent("WorkoutData-v5.sqlite")
            try migrateStore(
                from: workingURL,
                sourceModel: workingModel,
                to: destinationURL,
                destinationModel: version5.model,
                mapping: mapping
            )
            workingURL = destinationURL
            workingModel = version5.model
        }

        if source.version < 6 {
            let mapping: NSMappingModel
            do {
                mapping = try NSMappingModel.inferredMappingModel(
                    forSourceModel: workingModel,
                    destinationModel: version6.model
                )
            } catch {
                throw StagedMigrationError.mappingMissing(5, 6)
            }

            let destinationURL = migrationDirectory.appendingPathComponent("WorkoutData-v6.sqlite")
            try migrateStore(
                from: workingURL,
                sourceModel: workingModel,
                to: destinationURL,
                destinationModel: version6.model,
                mapping: mapping
            )
            workingURL = destinationURL
        }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: version6.model)
        try coordinator.replacePersistentStore(
            at: storeURL,
            destinationOptions: nil,
            withPersistentStoreFrom: workingURL,
            sourceOptions: nil,
            ofType: NSSQLiteStoreType
        )
        os_log(
            "Migrated WorkoutData store from v%d to v6",
            log: .migration,
            type: .info,
            source.version
        )
    }

    private static func migrateStore(
        from sourceURL: URL,
        sourceModel: NSManagedObjectModel,
        to destinationURL: URL,
        destinationModel: NSManagedObjectModel,
        mapping: NSMappingModel
    ) throws {
        let manager = NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
        try manager.migrateStore(
            from: sourceURL,
            sourceType: NSSQLiteStoreType,
            options: nil,
            with: mapping,
            toDestinationURL: destinationURL,
            destinationType: NSSQLiteStoreType,
            destinationOptions: nil
        )
    }

    private static func bundledModels() throws -> [VersionedModel] {
        let bundle = Bundle(for: WorkoutDataStorage.self)
        guard let modelDirectory = bundle.url(forResource: "WorkoutData", withExtension: "momd") else {
            throw StagedMigrationError.modelBundleMissing
        }

        let files: [(Int, String)] = [
            (1, "WorkoutData.mom"),
            (2, "WorkoutData v2.mom"),
            (3, "WorkoutData v3.mom"),
            (4, "WorkoutData v4.mom"),
            (5, "WorkoutData v5.mom"),
            (6, "WorkoutData v6.mom")
        ]
        return try files.map { version, fileName in
            let url = modelDirectory.appendingPathComponent(fileName)
            guard let versionModel = NSManagedObjectModel(contentsOf: url) else {
                throw StagedMigrationError.modelMissing(fileName)
            }
            return VersionedModel(version: version, model: versionModel)
        }
    }
}

extension WorkoutDataStorage {
    static func tryToRecoverFromMigrationError(context: NSManagedObjectContext) {
        context.performAndWait {
            let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
            workoutRequest.predicate = NSPredicate(format: "\(#keyPath(Workout.uuid)) == NULL")
            let workouts = try? context.fetch(workoutRequest)
            workouts?.forEach { $0.uuid = UUID() }
            (workouts?.count).map { os_log("Adding UUIDs for %d workouts", log: .migration, type: .info, $0) }
            
            let workoutExerciseRequest: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
            workoutExerciseRequest.predicate = NSPredicate(format: "\(#keyPath(WorkoutExercise.uuid)) == NULL")
            let workoutExercises = try? context.fetch(workoutExerciseRequest)
            workoutExercises?.forEach { $0.uuid = UUID() }
            (workoutExercises?.count).map { os_log("Adding UUIDs for %d workout exercises", log: .migration, type: .info, $0) }

            let workoutSetRequest: NSFetchRequest<WorkoutSet> = WorkoutSet.fetchRequest()
            workoutSetRequest.predicate = NSPredicate(format: "\(#keyPath(WorkoutSet.uuid)) == NULL")
            let workoutSets = try? context.fetch(workoutSetRequest)
            workoutSets?.forEach { $0.uuid = UUID() }
            (workoutSets?.count).map { os_log("Adding UUIDs for %d workout sets", log: .migration, type: .info, $0) }
            
            let workoutPlanRequest: NSFetchRequest<WorkoutPlan> = WorkoutPlan.fetchRequest()
            workoutPlanRequest.predicate = NSPredicate(format: "\(#keyPath(WorkoutPlan.uuid)) == NULL")
            let workoutPlans = try? context.fetch(workoutPlanRequest)
            workoutPlans?.forEach { $0.uuid = UUID() }
            (workoutPlans?.count).map { os_log("Adding UUIDs for %d workout plans", log: .migration, type: .info, $0) }
            
            let workoutRoutineRequest: NSFetchRequest<WorkoutRoutine> = WorkoutRoutine.fetchRequest()
            workoutRoutineRequest.predicate = NSPredicate(format: "\(#keyPath(WorkoutRoutine.uuid)) == NULL")
            let workoutRoutines = try? context.fetch(workoutRoutineRequest)
            workoutRoutines?.forEach { $0.uuid = UUID() }
            (workoutRoutines?.count).map { os_log("Adding UUIDs for %d workout routines", log: .migration, type: .info, $0) }
            
            let workoutRoutineExerciseRequest: NSFetchRequest<WorkoutRoutineExercise> = WorkoutRoutineExercise.fetchRequest()
            workoutRoutineExerciseRequest.predicate = NSPredicate(format: "\(#keyPath(WorkoutRoutineExercise.uuid)) == NULL")
            let workoutRoutineExercises = try? context.fetch(workoutRoutineExerciseRequest)
            workoutRoutineExercises?.forEach { $0.uuid = UUID() }
            (workoutRoutineExercises?.count).map { os_log("Adding UUIDs for %d workout routine exercises", log: .migration, type: .info, $0) }
            
            let workoutRoutineSetRequest: NSFetchRequest<WorkoutRoutineSet> = WorkoutRoutineSet.fetchRequest()
            workoutRoutineSetRequest.predicate = NSPredicate(format: "\(#keyPath(WorkoutRoutineSet.uuid)) == NULL")
            let workoutRoutineSets = try? context.fetch(workoutRoutineSetRequest)
            workoutRoutineSets?.forEach { $0.uuid = UUID() }
            (workoutRoutineSets?.count).map { os_log("Adding UUIDs for %d workout routine sets", log: .migration, type: .info, $0) }
        }
    }
}

import os.signpost
extension WorkoutDataStorage {
    public static func sendObjectsWillChange(changes: NSManagedObjectContext.ObjectChanges) {
        for changedObject in changes.inserted.union(changes.updated).union(changes.deleted) {
            // instruments debugging
            let signPostID = OSSignpostID(log: .coreDataMonitor)
            let signPostName: StaticString = "process single workout data change"
            os_signpost(.begin, log: .coreDataMonitor, name: signPostName, signpostID: signPostID, "%@", changedObject.objectID)
            defer { os_signpost(.end, log: .coreDataMonitor, name: signPostName, signpostID: signPostID) }
            //
            
            changedObject.objectWillChange.send()
            if let workout = changedObject as? Workout {
                workout.workoutExercises?.compactMap { $0 as? WorkoutExercise }
                    .forEach { workoutExercise in
                        workoutExercise.objectWillChange.send()
                        workoutExercise.workoutSets?.compactMap { $0 as? WorkoutSet }
                            .forEach { $0.objectWillChange.send() }
                }
            } else if let workoutExercise = changedObject as? WorkoutExercise {
                workoutExercise.workout?.objectWillChange.send()
                workoutExercise.workoutSets?.compactMap { $0 as? WorkoutSet }
                    .forEach { $0.objectWillChange.send() }
            } else if let workoutSet = changedObject as? WorkoutSet {
                workoutSet.workoutExercise?.objectWillChange.send()
                workoutSet.workoutExercise?.workout?.objectWillChange.send()
            } else if let workoutPlan = changedObject as? WorkoutPlan {
                workoutPlan.workoutRoutines?.compactMap { $0 as? WorkoutRoutine }
                    .forEach { workoutRoutine in
                        workoutRoutine.objectWillChange.send()
                        workoutRoutine.workoutRoutineExercises?.compactMap { $0 as? WorkoutRoutineExercise }
                            .forEach { workoutRoutineExercise in
                                workoutRoutineExercise.objectWillChange.send()
                                workoutRoutineExercise.workoutRoutineSets?.compactMap { $0 as? WorkoutRoutineSet }
                                    .forEach { $0.objectWillChange.send() }
                        }
                }
            } else if let workoutRoutine = changedObject as? WorkoutRoutine {
                workoutRoutine.workoutPlan?.objectWillChange.send()
                workoutRoutine.workoutRoutineExercises?.compactMap { $0 as? WorkoutRoutineExercise }
                    .forEach { workoutRoutineExercise in
                        workoutRoutineExercise.objectWillChange.send()
                        workoutRoutineExercise.workoutRoutineSets?.compactMap { $0 as? WorkoutRoutineSet }
                            .forEach { $0.objectWillChange.send() }
                }
            } else if let workoutRoutineExercise = changedObject as? WorkoutRoutineExercise {
                workoutRoutineExercise.workoutRoutine?.objectWillChange.send()
                workoutRoutineExercise.workoutRoutine?.workoutPlan?.objectWillChange.send()
                workoutRoutineExercise.workoutRoutineSets?.compactMap { $0 as? WorkoutRoutineSet }
                    .forEach { $0.objectWillChange.send() }
            } else if let workoutRoutineSet = changedObject as? WorkoutRoutineSet {
                workoutRoutineSet.workoutRoutineExercise?.objectWillChange.send()
                workoutRoutineSet.workoutRoutineExercise?.workoutRoutine?.objectWillChange.send()
                workoutRoutineSet.workoutRoutineExercise?.workoutRoutine?.workoutPlan?.objectWillChange.send()
            } else {
                os_log("Change for unknown NSManagedObject: %@", log: .coreDataMonitor, type: .error, changedObject)
            }
        }
    }
}
