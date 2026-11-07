//
//  CustomExercisesView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 17.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import CoreData
import WorkoutDataKit

struct CustomExercisesView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var exerciseStore: ExerciseStore
    
    @State private var activeSheet: SheetType?
    @State private var exerciseToDelete: Exercise?
    @State private var mutationFailure: CustomExerciseSaveFailure?
    
    private enum SheetType: Identifiable {
        case createCustomExercise
        case editCustomExercise(Exercise)
        
        var id: String {
            switch self {
            case .createCustomExercise:
                return "create-custom-exercise"
            case .editCustomExercise(let exercise):
                return "edit-custom-exercise-\(exercise.uuid.uuidString)"
            }
        }
    }
    
    private func sheetView(type: SheetType) -> AnyView {
        switch type {
        case .createCustomExercise:
            return CreateCustomExerciseSheet()
                .environmentObject(exerciseStore)
                .typeErased
        case .editCustomExercise(let exercise):
            return EditCustomExerciseSheet(exercise: exercise)
                .environmentObject(exerciseStore)
                .typeErased
        }
    }
    
    private func delete(_ exercise: Exercise) {
        assert(exercise.isCustom)
        let customExerciseSnapshot = exerciseStore.customExercises
        do {
            try exerciseStore.deleteCustomExercise(with: exercise.uuid)
            try deleteWorkoutExercises(with: exercise.uuid)
            try managedObjectContext.save()

            let feedbackGenerator = UINotificationFeedbackGenerator()
            feedbackGenerator.prepare()
            feedbackGenerator.notificationOccurred(.success)
        } catch {
            managedObjectContext.rollback()
            try? exerciseStore.replaceCustomExercises(with: customExerciseSnapshot)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                mutationFailure = CustomExerciseSaveFailure(error: error)
            }
        }
    }

    var body: some View {
        List {
            if exerciseStore.customExercises.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Custom Exercises", systemImage: "dumbbell.fill")
                    } description: {
                        Text("Create an exercise to start building your library.")
                    } actions: {
                        Button("Create Exercise") { activeSheet = .createCustomExercise }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(exerciseStore.orderedByRecency(exerciseStore.customExercises)) { exercise in
                        customExerciseRow(exercise)
                    }
                } header: {
                    Text("Your Library")
                } footer: {
                    Text("\(exerciseStore.customExercises.count) custom exercise\(exerciseStore.customExercises.count == 1 ? "" : "s") · private to liteweight")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Custom Exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create Exercise", systemImage: "plus") {
                    activeSheet = .createCustomExercise
                }
                .labelStyle(.iconOnly)
                .accessibilityHint("Opens the custom exercise editor")
            }
        }
        .sheet(item: $activeSheet) { type in
            self.sheetView(type: type)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete \(exerciseToDelete?.title ?? "exercise")?",
            isPresented: Binding(
                get: { exerciseToDelete != nil },
                set: { if !$0 { exerciseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Exercise", role: .destructive) {
                guard let exercise = exerciseToDelete else { return }
                exerciseToDelete = nil
                delete(exercise)
            }
            Button("Cancel", role: .cancel) {
                exerciseToDelete = nil
            }
        } message: {
            Text("This removes the custom exercise and every workout set that uses it. This cannot be undone.")
        }
        .sheet(item: $mutationFailure) { failure in
            LiteweightStatusSheet(
                headerTitle: "Custom Exercises",
                title: "Could not delete exercise",
                message: failure.error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                tint: .red
            )
        }
    }

    private func customExerciseRow(_ exercise: Exercise) -> some View {
        NavigationLink {
            ExerciseDetailView(exercise: exercise)
                .environmentObject(self.settingsStore)
        } label: {
            ExerciseLibraryRow(exercise: exercise)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                exerciseToDelete = exercise
            }
            Button("Edit", systemImage: "pencil") {
                activeSheet = .editCustomExercise(exercise)
            }
            .tint(.accentColor)
        }
        .contextMenu {
            Button("Edit Exercise", systemImage: "pencil") {
                activeSheet = .editCustomExercise(exercise)
            }
            Button("Delete Exercise", systemImage: "trash", role: .destructive) {
                exerciseToDelete = exercise
            }
        }
    }

    private func deleteWorkoutExercises(with uuid: UUID) throws {
        let request: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(WorkoutExercise.exerciseUuid)) == %@", uuid as CVarArg)
        let workoutExercises = try managedObjectContext.fetch(request)
        workoutExercises.forEach { managedObjectContext.delete($0) }
    }
}

#if DEBUG
struct CustomExercisesView_Previews: PreviewProvider {
    static var previews: some View {
        CustomExercisesView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
