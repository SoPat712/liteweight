//
//  WorkoutDataMigrationTests.swift
//  liteweightTests
//
//  Created by Karim Abou Zeid on 26.03.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import XCTest
import CoreData
@testable import WorkoutDataKit

class WorkoutDataMigrationTests: XCTestCase {
    var testFolder: URL!
    var storeURL: URL!
    var persistentContainer: NSPersistentContainer!
    let exerciseStore = ExerciseStore(customExercisesURL: nil)
    
    override func setUpWithError() throws {
        testFolder = FileManager.default.temporaryDirectory.appendingPathComponent("test", isDirectory: true)
        storeURL = testFolder.appendingPathComponent("WorkoutData").appendingPathExtension("sqlite")
        try createCleanTestFolder()
        
        persistentContainer = NSPersistentContainer(name: "WorkoutData", managedObjectModel: WorkoutDataStorage.model)
    }
    
    override func tearDownWithError() throws {
        if let coordinator = persistentContainer?.persistentStoreCoordinator {
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
        persistentContainer = nil
        try wipeTestFolder()
    }
    
    func testMigrateFromV1() throws {
        prepareMigrationTest(workoutData: "modelv1_ironv1.0.0", allowInferMappingModel: false)
        
        let expectation = XCTestExpectation(description: "Load persistent stores")
        persistentContainer.loadPersistentStores { (description, error) in
            XCTAssertNil(error)
            
            let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
            let workouts = try! self.persistentContainer.viewContext.fetch(workoutRequest)
            XCTAssertEqual(workouts.count, 194) // sanity check
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testMigrateFromV2() throws {
        prepareMigrationTest(workoutData: "modelv2_ironv1.0.7", allowInferMappingModel: false)
        
        let expectation = XCTestExpectation(description: "Load persistent stores")
        persistentContainer.loadPersistentStores { (description, error) in
            XCTAssertNil(error)
            
            let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
            let workouts = try! self.persistentContainer.viewContext.fetch(workoutRequest)
            XCTAssertEqual(workouts.count, 246) // sanity check
            XCTAssertTrue(workouts.allSatisfy { $0.importSource == nil && $0.healthExportState == nil })
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testMigrateFromV3() throws {
        prepareMigrationTest(workoutData: "modelv3_ironv1.1.0", allowInferMappingModel: false)
        
        let expectation = XCTestExpectation(description: "Load persistent stores")
        persistentContainer.loadPersistentStores { (description, error) in
            XCTAssertNil(error)
            
            let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
            let workouts = try! self.persistentContainer.viewContext.fetch(workoutRequest)
            XCTAssertEqual(workouts.count, 246) // sanity check
            XCTAssertTrue(workouts.allSatisfy { $0.importSource == nil && $0.healthExportState == nil })
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }

    func testMigrateFromV5PreservesWorkoutsAsNative() throws {
        try checkAdditiveMigration(from: 5)
    }

    func testMigrateFromV4ThroughV5ToV6() throws {
        try checkAdditiveMigration(from: 4)
    }

    private func checkAdditiveMigration(from version: Int) throws {
        let bundle = Bundle(for: WorkoutDataStorage.self)
        let directory = try XCTUnwrap(bundle.url(forResource: "WorkoutData", withExtension: "momd"))
        let sourceModel = try XCTUnwrap(NSManagedObjectModel(
            contentsOf: directory.appendingPathComponent("WorkoutData v\(version).mom")
        ))
        XCTAssertNil(sourceModel.entitiesByName["Workout"]?.attributesByName["importSource"])
        XCTAssertNil(sourceModel.entitiesByName["Workout"]?.attributesByName["healthExportState"])
        // Use generic objects for the old schema, not current model subclasses.
        sourceModel.entities.forEach { $0.managedObjectClassName = "NSManagedObject" }
        let sourceCoordinator = NSPersistentStoreCoordinator(managedObjectModel: sourceModel)
        let sourceStore = try sourceCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL
        )
        let sourceContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        sourceContext.persistentStoreCoordinator = sourceCoordinator
        let workout = NSEntityDescription.insertNewObject(forEntityName: "Workout", into: sourceContext)
        let id = UUID()
        workout.setValue(id, forKey: "uuid")
        workout.setValue("Existing workout", forKey: "title")
        workout.setValue(Date(timeIntervalSince1970: 1_000), forKey: "start")
        workout.setValue(Date(timeIntervalSince1970: 2_000), forKey: "end")
        try sourceContext.save()
        sourceContext.reset()
        try sourceCoordinator.remove(sourceStore)

        try WorkoutDataStorage.migrateStoreIfNeeded(at: storeURL)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: storeURL
        )
        XCTAssertTrue(WorkoutDataStorage.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))
        let attribute = try XCTUnwrap(WorkoutDataStorage.model.entitiesByName["Workout"]?.attributesByName["importSource"])
        XCTAssertEqual(attribute.attributeType, .stringAttributeType)
        XCTAssertTrue(attribute.isOptional)
        let stateAttribute = try XCTUnwrap(WorkoutDataStorage.model.entitiesByName["Workout"]?.attributesByName["healthExportState"])
        XCTAssertEqual(stateAttribute.attributeType, .stringAttributeType)
        XCTAssertTrue(stateAttribute.isOptional)
        try persistentContainer.persistentStoreCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL
        )
        let migrated = try persistentContainer.viewContext.fetch(Workout.fetchRequest())
        XCTAssertEqual(migrated.count, 1)
        let existing = try XCTUnwrap(migrated.first)
        XCTAssertEqual(existing.uuid, id)
        XCTAssertEqual(existing.title, "Existing workout")
        XCTAssertEqual(existing.duration, 1_000)
        XCTAssertNil(existing.importSource)
        XCTAssertNil(existing.healthExportState)
        XCTAssertFalse(existing.isImported)
        // A second pass must recognize the current store without rewriting it.
        XCTAssertNoThrow(try WorkoutDataStorage.migrateStoreIfNeeded(at: storeURL))
    }

}

extension WorkoutDataMigrationTests {
    func prepareMigrationTest(workoutData: String, allowInferMappingModel: Bool) {
        // sanity check that we have a fresh copy of the database
        precondition(!FileManager.default.fileExists(atPath: storeURL.path))
        try! copyWorkoutData(name: workoutData)
        precondition(FileManager.default.fileExists(atPath: storeURL.path))
        
        // sanity check that the store files need migration
        let metadata = try! NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL, options: nil)
        precondition(WorkoutDataStorage.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) == false)

        // Production performs a deliberate staged migration so the legacy
        // UUID/exercise-ID policies run before the additive current schema.
        try! WorkoutDataStorage.migrateStoreIfNeeded(at: storeURL)
        let migratedMetadata = try! NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
        precondition(WorkoutDataStorage.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: migratedMetadata))
        
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = allowInferMappingModel
        persistentContainer.persistentStoreDescriptions = [description]
    }
}

extension WorkoutDataMigrationTests {
    func copyWorkoutData(name: String) throws {
        let url = Bundle.init(for: Self.self).bundleURL.appendingPathComponent("workout_data").appendingPathComponent(name)
        precondition(FileManager.default.fileExists(atPath: url.path), "File \(url.path) does not exist")
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        try contents.forEach { try FileManager.default.copyItem(at: $0, to: testFolder.appendingPathComponent($0.lastPathComponent)) }
    }
}

extension WorkoutDataMigrationTests {
    func wipeTestFolder() throws {
        if FileManager.default.fileExists(atPath: testFolder.path) {
            try FileManager.default.removeItem(at: testFolder)
        }
    }
    
    func createCleanTestFolder() throws {
        try wipeTestFolder()
        try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
    }
}
