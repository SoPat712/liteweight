//
//  UserDefaults+Misc.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 02.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation

extension UserDefaults {
    enum MiscKeys: String {
        case finishedWorkoutsCount
        case watchWorkoutUuid
    }
    
    var finishedWorkoutsCount: Int {
        set {
            self.set(newValue, forKey: MiscKeys.finishedWorkoutsCount.rawValue)
        }
        get {
            self.integer(forKey: MiscKeys.finishedWorkoutsCount.rawValue)
        }
    }
    
    var watchWorkoutUuid: UUID? {
        set {
            self.set(newValue?.uuidString, forKey: MiscKeys.watchWorkoutUuid.rawValue)
        }
        get {
            guard let uuidString = self.string(forKey: MiscKeys.watchWorkoutUuid.rawValue) else { return nil }
            return UUID(uuidString: uuidString)
        }
    }
}
