//
//  EditCurrentWorkoutTimeView.swift
//  liteweight
//
//  A draft-based Cupertino editor for the active workout clock.
//

import SwiftUI
import WorkoutDataKit

struct EditCurrentWorkoutTimeView: View {
    @ObservedObject private var workout: Workout

    private let onApply: () -> Void

    @State private var draftStart: Date
    @State private var draftEnd: Date
    @State private var tracksAutomatically: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    init(workout: Workout, onApply: @escaping () -> Void = {}) {
        self.workout = workout
        self.onApply = onApply

        let start = workout.safeStart
        let end = max(workout.safeEnd, start)
        _draftStart = State(initialValue: start)
        _draftEnd = State(initialValue: end)
        _tracksAutomatically = State(initialValue: workout.end == nil)
    }

    private var effectiveEnd: Date {
        tracksAutomatically ? Date() : max(draftEnd, draftStart)
    }

    private var draftDuration: TimeInterval {
        max(effectiveEnd.timeIntervalSince(draftStart), 0)
    }

    private var latestStartDate: Date {
        min(effectiveEnd, Date())
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Duration") {
                    Text(durationTitle)
                        .font(.liteweightMetric(.body, weight: .semibold))
                        .contentTransition(.numericText())
                }
                Toggle("Track Time Automatically", isOn: $tracksAutomatically)
            } footer: {
                Text(tracksAutomatically
                     ? "The clock keeps running with your workout."
                     : "Choose a fixed end time below.")
            }

            Section {
                DatePicker(
                    "Started",
                    selection: $draftStart,
                    in: Date.distantPast...latestStartDate,
                    displayedComponents: [.date, .hourAndMinute]
                )

                if !tracksAutomatically {
                    DatePicker(
                        "Ended",
                        selection: $draftEnd,
                        in: draftStart...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            } footer: {
                Text("Sets and elapsed time are measured from the start.")
            }

            Section {
                Button("Reset Start to Now") {
                    let now = Date()
                    draftStart = now
                    if !tracksAutomatically {
                        draftEnd = now
                    }
                }

                Button("Apply Workout Time", action: applyDraft)
                    .fontWeight(.semibold)
            } footer: {
                Text("Changes only take effect after you apply them.")
            }
        }
        .listStyle(.insetGrouped)
        .animation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion), value: tracksAutomatically)
        .onChange(of: draftStart) { _, newStart in
            if !tracksAutomatically, draftEnd < newStart {
                draftEnd = newStart
            }
        }
        .onChange(of: tracksAutomatically) { _, automatic in
            if !automatic {
                draftEnd = max(Date(), draftStart)
            }
        }
        .sensoryFeedback(.selection, trigger: tracksAutomatically)
    }

    private var durationTitle: String {
        durationFormatter.string(from: draftDuration) ?? "00:00"
    }

    private func applyDraft() {
        workout.start = draftStart
        workout.end = tracksAutomatically ? nil : max(draftEnd, draftStart)
        onApply()
    }
}

#if DEBUG
struct EditCurrentWorkoutTimeView_Previews: PreviewProvider {
    static var previews: some View {
        EditCurrentWorkoutTimeView(workout: MockWorkoutData.metricRandom.currentWorkout)
            .preferredColorScheme(.dark)
    }
}
#endif
