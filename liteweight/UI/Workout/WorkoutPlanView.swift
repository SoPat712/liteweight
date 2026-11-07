//
//  WorkoutPlanView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 21.12.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

/// The editor for a saved workout plan.
///
/// Plans are edited relatively infrequently, while the card layout keeps the title,
/// routine summaries, and the destructive controls visually separate in both
/// light and dark appearances.
struct WorkoutPlanView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var exerciseStore: ExerciseStore
    @Environment(\.managedObjectContext) var managedObjectContext

    @ObservedObject var workoutPlan: WorkoutPlan

    @State private var workoutPlanTitleInput: String?
    @State private var routineToDelete: WorkoutRoutine?

    private var workoutPlanTitle: Binding<String> {
        Binding(
            get: { workoutPlanTitleInput ?? workoutPlan.title ?? "" },
            set: { workoutPlanTitleInput = $0 }
        )
    }

    private var workoutRoutines: [WorkoutRoutine] {
        workoutPlan.workoutRoutines?.array as? [WorkoutRoutine] ?? []
    }

    private func saveWorkoutPlanTitle() {
        guard let input = workoutPlanTitleInput else { return }
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        workoutPlanTitleInput = title
        workoutPlan.title = title.isEmpty ? nil : title
        managedObjectContext.saveOrCrash()
    }

    private func createWorkoutRoutine() {
        let workoutRoutine = WorkoutRoutine.create(context: managedObjectContext)
        workoutRoutine.workoutPlan = workoutPlan
        managedObjectContext.saveOrCrash()
    }

    private func moveRoutine(from source: Int, to destination: Int) {
        guard source != destination,
              workoutRoutines.indices.contains(source),
              workoutRoutines.indices.contains(destination) else { return }

        var reordered = workoutRoutines
        let routine = reordered.remove(at: source)
        reordered.insert(routine, at: destination)
        workoutPlan.workoutRoutines = NSOrderedSet(array: reordered)
        managedObjectContext.saveOrCrash()
    }

    /// Returns true when deleting a routine also removes the user's saved plan
    /// exercises. This preserves the confirmation behavior of the old editor.
    private func needsConfirmBeforeDelete(_ routine: WorkoutRoutine) -> Bool {
        (routine.workoutRoutineExercises?.count ?? 0) > 0
    }

    private func requestDelete(_ routine: WorkoutRoutine) {
        if needsConfirmBeforeDelete(routine) {
            routineToDelete = routine
        } else {
            delete(routine)
        }
    }

    private func delete(_ routine: WorkoutRoutine) {
        managedObjectContext.delete(routine)
        managedObjectContext.saveOrCrash()
    }

    var body: some View {
        List {
            Section("Workout Details") {
                TextField("Workout title", text: workoutPlanTitle, onEditingChanged: { isEditing in
                    if !isEditing { saveWorkoutPlanTitle() }
                })
                .textInputAutocapitalization(.words)
            }

            Section {
                if workoutRoutines.isEmpty {
                    ContentUnavailableView {
                        Label("No Workouts Yet", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("Add a workout to start choosing exercises.")
                    }
                } else {
                    ForEach(Array(workoutRoutines.enumerated()), id: \.element.id) { index, routine in
                        routineRow(routine, index: index)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                    .onMove { source, destination in
                        guard let first = source.first else { return }
                        moveRoutine(from: first, to: destination > first ? destination - 1 : destination)
                    }
                }
            } header: {
                Text("Workouts")
            }

            Section {
                Button("Add Workout", systemImage: "plus", action: createWorkoutRoutine)
            }
        }
        .listStyle(.insetGrouped)
        .animation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion), value: workoutRoutines.map(\.objectID))
        .navigationTitle(workoutPlan.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 36)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { saveWorkoutPlanTitle() }
            }
        }
        .alert(item: $routineToDelete) { routine in
            Alert(
                title: Text("Delete \(routine.displayTitle)?"),
                message: Text("This will remove the exercises saved in this workout and cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    delete(routine)
                },
                secondaryButton: .cancel()
            )
        }
        .onDisappear {
            saveWorkoutPlanTitle()
        }
    }

    private func routineRow(_ routine: WorkoutRoutine, index: Int) -> some View {
        NavigationLink(destination: WorkoutRoutineView(workoutRoutine: routine)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.displayTitle)
                    .font(.headline)
                    .foregroundStyle(LiteweightTheme.primaryText)
                    .lineLimit(1)
                Text(routine.subtitle(in: exerciseStore.exercises))
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                requestDelete(routine)
            }
        }
        .contextMenu {
            if index > 0 {
                Button("Move Up", systemImage: "arrow.up") { moveRoutine(from: index, to: index - 1) }
            }
            if index < workoutRoutines.count - 1 {
                Button("Move Down", systemImage: "arrow.down") { moveRoutine(from: index, to: index + 1) }
            }
            Button("Delete Workout", systemImage: "trash", role: .destructive) {
                requestDelete(routine)
            }
        }
    }
}

#if DEBUG
struct WorkoutPlanView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WorkoutPlanView(workoutPlan: MockWorkoutData.metric.workoutPlan)
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
