//
//  Codable+NSManagedObjectContext.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 26.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation

public extension CodingUserInfoKey {
    static let managedObjectContextKey = CodingUserInfoKey(rawValue: "managedObjectContextKey")
    static let exercisesKey = CodingUserInfoKey(rawValue: "exercisesKey")
    static let preserveWorkoutProvenance = CodingUserInfoKey(rawValue: "preserveWorkoutProvenance")!
    
    enum DecodingError: Error {
        case managedObjectContextMissing
    }
}
