//
//  ExerciseSingleSelectionView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 20.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct ExerciseSingleSelectionView: View {
    var exerciseGroups: [ExerciseGroup]
    var onSelection: (Exercise) -> Void
    
    var body: some View {
        List {
            ExerciseRecencyListContent(exerciseGroups: exerciseGroups) { exercise in
                Button {
                    onSelection(exercise)
                } label: {
                    ExerciseLibraryRow(exercise: exercise)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

#if DEBUG
struct ExerciseSingleSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseSingleSelectionView(exerciseGroups: ExerciseStore.splitIntoMuscleGroups(exercises: ExerciseStore.shared.shownExercises)) { _ in }
            .environmentObject(ExerciseStore.shared)
    }
}
#endif
