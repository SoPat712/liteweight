//
//  EditCustomExerciseSheet.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 23.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct EditCustomExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var exerciseStore: ExerciseStore
    @State private var exerciseValues: EditCustomExerciseView.ExerciseValues
    @State private var saveFailure: CustomExerciseSaveFailure?
    @State private var isSelectingMuscles = false
    private let exercise: Exercise
    
    init(exercise: Exercise) {
        self.exercise = exercise
        let primaryMuscle = exercise.primaryMuscle.map { EditCustomExerciseView.ExerciseValues.ExerciseMuscle(type: .primary, muscle: $0) }
        let secondaryMuscle = exercise.secondaryMuscle.map { EditCustomExerciseView.ExerciseValues.ExerciseMuscle(type: .secondary, muscle: $0) }
        _exerciseValues = State(
            initialValue: .init(
                title: exercise.title,
                description: exercise.description ?? "",
                muscles: Set(primaryMuscle + secondaryMuscle),
                type: exercise.type,
                stepsText: exercise.steps.joined(separator: "\n"),
                tipsText: exercise.tips.joined(separator: "\n")
            )
        )
    }

    private var trimmedTitle: String {
        exerciseValues.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasDuplicateTitle: Bool {
        exerciseStore.exercises.contains {
            $0.uuid != exercise.uuid &&
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmedTitle) == .orderedSame
        }
    }

    private var hasPrimaryMuscle: Bool {
        exerciseValues.muscles.contains { $0.type == .primary }
    }

    private var titleValidationMessage: String? {
        guard !trimmedTitle.isEmpty, hasDuplicateTitle else { return nil }
        return "An exercise with this name already exists."
    }
    
    private var canSave: Bool {
        !trimmedTitle.isEmpty && !hasDuplicateTitle && hasPrimaryMuscle
    }
    
    private func saveExercise() {
        let title = self.exerciseValues.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = self.exerciseValues.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryMuscle = self.exerciseValues.muscles
            .map { $0 }
            .filter { $0.type == .primary }
            .sorted { $0.shortDisplayTitle < $1.shortDisplayTitle }
            .map { $0.muscle }
        let secondaryMuscle = self.exerciseValues.muscles
            .map { $0 }
            .filter { $0.type == .secondary }
            .sorted { $0.shortDisplayTitle < $1.shortDisplayTitle }
            .map { $0.muscle }
        do {
            try exerciseStore.updateCustomExercise(
                with: exercise.uuid,
                title: title,
                description: description.isEmpty ? nil : description,
                primaryMuscle: primaryMuscle,
                secondaryMuscle: secondaryMuscle,
                type: exerciseValues.type,
                steps: exerciseValues.steps,
                tips: exerciseValues.tips
            )
            dismiss()

            let feedbackGenerator = UINotificationFeedbackGenerator()
            feedbackGenerator.prepare()
            feedbackGenerator.notificationOccurred(.success)
        } catch {
            saveFailure = CustomExerciseSaveFailure(error: error)
        }
    }
    
    var body: some View {
        NavigationStack {
            EditCustomExerciseView(
                exerciseValues: $exerciseValues,
                titleValidationMessage: titleValidationMessage,
                onSelectMuscles: { isSelectingMuscles = true }
            )
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveExercise)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .navigationDestination(isPresented: $isSelectingMuscles) {
                MuscleSelectionView(
                    muscles: Exercise.muscleNames,
                    selection: $exerciseValues.muscles
                )
                .navigationTitle("Select Muscles")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $saveFailure) { failure in
            LiteweightStatusSheet(
                headerTitle: "Edit Exercise",
                title: "Could not save changes",
                message: failure.error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                tint: .red
            )
        }
    }
}
