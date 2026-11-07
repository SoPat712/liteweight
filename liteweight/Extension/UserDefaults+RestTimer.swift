//
//  UserDefaults+RestTimer.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 12.08.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation

extension UserDefaults {
    enum RestTimerKeys: String {
        case restTimerStart
        case restTimerDuration
        case restTimerPausedRemaining
        case recentRestTimes
    }
    
    var restTimerStart: Date? {
        set {
            self.set(newValue, forKey: RestTimerKeys.restTimerStart.rawValue)
        }
        get {
            guard let date = self.object(forKey: RestTimerKeys.restTimerStart.rawValue) as? Date else { return nil }
            guard date <= Date() else { return nil } // sanity check
            return date
        }
    }
    
    var restTimerDuration: TimeInterval? {
        set {
            self.set(newValue, forKey: RestTimerKeys.restTimerDuration.rawValue)
        }
        get {
            guard let duration = self.object(forKey: RestTimerKeys.restTimerDuration.rawValue) as? TimeInterval else { return nil }
            guard duration > 0 else { return nil } // sanity check
            return duration
        }
    }

    /// A paused timer keeps its remaining seconds without pretending that an
    /// end date is still advancing. This survives app relaunches and lets the
    /// logger, Live Activity, and Watch all render a truthful paused state.
    var restTimerPausedRemaining: TimeInterval? {
        set {
            if let value = newValue {
                self.set(value, forKey: RestTimerKeys.restTimerPausedRemaining.rawValue)
            } else {
                self.removeObject(forKey: RestTimerKeys.restTimerPausedRemaining.rawValue)
            }
        }
        get {
            guard let value = object(forKey: RestTimerKeys.restTimerPausedRemaining.rawValue) as? TimeInterval,
                  value > 0 else { return nil }
            return value
        }
    }
    
    var recentRestTimes: [TimeInterval] {
        set {
            assert(newValue.uniqed() == newValue)
            self.set(Array(newValue.prefix(5)), forKey: RestTimerKeys.recentRestTimes.rawValue)
        }
        get {
            self.object(forKey: RestTimerKeys.recentRestTimes.rawValue) as? [TimeInterval] ?? []
        }
    }
}
