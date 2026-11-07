//
//  WorkoutTab.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 11.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct WorkoutTab: View {
    var onOpenCurrentWorkout: () -> Void = {}
    
    var body: some View {
        StartWorkoutView(onOpenCurrentWorkout: onOpenCurrentWorkout)
    }
}

#if DEBUG
struct WorkoutTab_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutTab()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
