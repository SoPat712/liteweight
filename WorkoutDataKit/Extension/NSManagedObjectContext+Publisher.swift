//
//  NSManagedObjectContext+Publisher.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 08.08.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import Combine
import CoreData
import os.log
import os.signpost

extension NSManagedObjectContext {
    /// Run on this context's queue. On failure, undo only this mutation, not
    /// unrelated user edits that were already pending when it began.
    public func persistMutation<T>(
        save: () throws -> Void,
        mutation: () throws -> T
    ) throws -> T {
        processPendingChanges()
        let previousUndoManager = undoManager
        let mutationUndoManager = UndoManager()
        mutationUndoManager.groupsByEvent = false
        undoManager = mutationUndoManager
        defer { undoManager = previousUndoManager }

        mutationUndoManager.beginUndoGrouping()
        do {
            let result = try mutation()
            processPendingChanges()
            mutationUndoManager.endUndoGrouping()
            try save()
            return result
        } catch {
            processPendingChanges()
            if mutationUndoManager.groupingLevel > 0 {
                mutationUndoManager.endUndoGrouping()
            }
            mutationUndoManager.undo()
            processPendingChanges()
            throw error
        }
    }
}

extension NSManagedObjectContext {
    public struct ObjectChanges {
        public let inserted: Set<NSManagedObject>
        public let updated: Set<NSManagedObject>
        public let deleted: Set<NSManagedObject>
    }
    
    private static let publisher: AnyPublisher<(ObjectChanges, NSManagedObjectContext), Never> = {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)
            .compactMap { notification -> (ObjectChanges, NSManagedObjectContext)? in
                guard let userInfo = notification.userInfo else { return nil }
                guard let managedObjectContext = notification.object as? NSManagedObjectContext else { return nil }
                
                let signPostID = OSSignpostID(log: .coreDataMonitor)
                let signPostName: StaticString = "process MOC change notification"
                os_signpost(.begin, log: .coreDataMonitor, name: signPostName, signpostID: signPostID)
                defer { os_signpost(.end, log: .coreDataMonitor, name: signPostName, signpostID: signPostID) }

                let inserted = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? Set()
                let updated = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? Set()
                let deleted = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? Set()
                
                os_log("Received change notification inserted=%d updated=%d deleted=%d", log: .coreDataMonitor, type: .debug, inserted.count, updated.count, deleted.count)
                return (ObjectChanges(inserted: inserted, updated: updated, deleted: deleted), managedObjectContext)
            }
            .share()
            .eraseToAnyPublisher()
    }()
    
    public var publisher: AnyPublisher<ObjectChanges, Never> {
        Self.publisher
            .filter { $0.1 === self } // only publish changes belonging to this context
            .map { $0.0 }
            .eraseToAnyPublisher()
    }
}
