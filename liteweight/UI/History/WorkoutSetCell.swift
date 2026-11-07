//
//  WorkoutSetCell.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 28.08.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct WorkoutSetCell: View {
    @EnvironmentObject var settingsStore: SettingsStore

    @ObservedObject var workoutSet: WorkoutSet
    let index: Int
    var colorMode: ColorMode = .activated
    var isPlaceholder = false
    var showCompleted = false
    var showUpNextIndicator = false
    
    enum ColorMode {
        case selected
        case activated
        case deactivated
        case disabled
    }
    
    private func titleView(isPlaceholder: Bool, colorMode: ColorMode) -> some View {
        HStack {
            if isPlaceholder {
                Text("Set")
                    .foregroundColor(.secondary)
            } else {
                Text(workoutSet.displayTitle(weightUnit: settingsStore.weightUnit))
                    .font(.liteweightMetric(.body))
                    .foregroundColor(colorMode == .disabled ? .secondary : .primary)
            }
        }
    }
    
    private static var rpeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
    
    var body: some View {
        HStack {
            if showUpNextIndicator {
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundColor(LiteweightTheme.accent)
            } else if showCompleted && workoutSet.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(colorMode == .disabled ? LiteweightTheme.secondaryText : LiteweightTheme.accent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    titleView(isPlaceholder: isPlaceholder, colorMode: colorMode)
                        .background(
                            Group {
                                if colorMode == .selected {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(Color.accentColor)
                                        .padding(-4)
                                }
                            }
                        )
                    
                    if let interval = WorkoutRoutineSetCell.repetitionIntervalString(minRepetitions: workoutSet.minTargetRepetitions?.intValue, maxRepetitions: workoutSet.maxTargetRepetitions?.intValue) {
                        Group {
                            if !isPlaceholder {
                                Text("/")
                            }
                            
                            Text("\(interval)")
                                .font(.liteweightMetric(.body, weight: .semibold))
                        }
                        .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                
                workoutSet.comment.map {
                    Text($0.enquoted)
                        .lineLimit(1)
                        .font(Font.caption.italic())
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let rpe = workoutSet.rpeValue {
                Text("RPE " + (Self.rpeFormatter.string(from: NSNumber(value: rpe)) ?? String(format: "%.1f", rpe)))
                    .modifier(TagStyle())
            }
            
            if workoutSet.isPersonalRecord ?? false {
                Image(systemName: "trophy.fill")
                    .foregroundColor(colorMode == .disabled ? LiteweightTheme.secondaryText : LiteweightTheme.metricRecord)
                    .padding(6)
                    .background(LiteweightTheme.metricRecordContainer, in: Circle())
                    .accessibilityLabel("Personal record")
            }

            Text("\(index)")
                .font(.liteweightMetric(.body, weight: .semibold))
                .foregroundColor(workoutSet.tagValue != nil ? .clear : .secondary)
                .background(
                    Group {
                        workoutSet.tagValue.map {
                            Text($0.title.first!.uppercased())
                                .fontWeight(.semibold)
                                .foregroundColor($0 == .warmUp ? LiteweightTheme.metricSets : LiteweightTheme.secondaryText)
                                .fixedSize()
                        }
                    }
                )
        }
    }
}

private struct TagStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.liteweightMetric(.caption, weight: .semibold))
            .foregroundColor(LiteweightTheme.metricEffort)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LiteweightTheme.metricEffortContainer, in: Capsule())
    }
}

#if DEBUG
struct WorkoutSetCell_Previews: PreviewProvider {
    static var workoutSet1: WorkoutSet = {
        let set = WorkoutSet(context: MockWorkoutData.metric.context)
        set.weightValue = 82.5
        set.repetitionsValue = 5
        return set
    }()
    
    static var workoutSet2: WorkoutSet = {
        let set = WorkoutSet(context: MockWorkoutData.metric.context)
        set.weightValue = 82.5
        set.repetitionsValue = 5
        set.tagValue = .dropSet
        set.comment = "This is a comment"
        set.isCompleted = true
        return set
    }()
    
    static var workoutSet3: WorkoutSet = {
        let set = WorkoutSet(context: MockWorkoutData.metric.context)
        set.weightValue = 82.5
        set.repetitionsValue = 5
        set.minTargetRepetitionsValue = 8
        set.maxTargetRepetitionsValue = 12
        return set
    }()
    
    static var workoutSet4: WorkoutSet = {
        let set = WorkoutSet(context: MockWorkoutData.metric.context)
        set.weightValue = 82.5
        set.repetitionsValue = 5
        set.maxTargetRepetitionsValue = 12
        set.rpeValue = 7.5
        set.isCompleted = true
        return set
    }()
    
    static var workoutSet5: WorkoutSet = {
        let set = WorkoutSet(context: MockWorkoutData.metric.context)
        set.weightValue = 82.5
        set.repetitionsValue = 5
        set.minTargetRepetitionsValue = 8
        set.rpeValue = 8
        set.isCompleted = true
        return set
    }()
    
    static var workoutSet6: WorkoutSet = {
        let set = WorkoutSet(context: MockWorkoutData.metric.context)
        set.weightValue = 82.5
        set.repetitionsValue = 5
        set.minTargetRepetitionsValue = 5
        set.maxTargetRepetitionsValue = 5
        set.isCompleted = true
        set.comment = "This is a comment"
        return set
    }()
    
    static var workoutSet7: WorkoutSet = {
        let set = WorkoutSet(context: MockWorkoutData.metric.context)
        set.weightValue = 82.5
        set.repetitionsValue = 5
        set.isCompleted = true
        return set
    }()
    
    static var workoutSet8: WorkoutSet = {
        let set = WorkoutSet(context: MockWorkoutData.metric.context)
        set.weightValue = 132.5
        set.repetitionsValue = 3
        set.minTargetRepetitionsValue = 1
        set.rpeValue = 10
        set.isCompleted = true
        return set
    }()
    
    static var previews: some View {
        List {
            Section {
                WorkoutSetCell(workoutSet: workoutSet6, index: 1, showCompleted: true)
                WorkoutSetCell(workoutSet: workoutSet6, index: 2, colorMode: .selected, showCompleted: true)
                WorkoutSetCell(workoutSet: workoutSet8, index: 4, showCompleted: true)
                WorkoutSetCell(workoutSet: workoutSet7, index: 5, showUpNextIndicator: true)
                WorkoutSetCell(workoutSet: workoutSet3, index: 6, isPlaceholder: true)
                WorkoutSetCell(workoutSet: workoutSet6, index: 7, isPlaceholder: true)
                WorkoutSetCell(workoutSet: workoutSet1, index: 8, isPlaceholder: true)
            }
            
            Section {
                WorkoutSetCell(workoutSet: workoutSet1, index: 1)
                WorkoutSetCell(workoutSet: workoutSet2, index: 2)
                WorkoutSetCell(workoutSet: workoutSet3, index: 3)
                WorkoutSetCell(workoutSet: workoutSet4, index: 4)
                WorkoutSetCell(workoutSet: workoutSet5, index: 5)
                WorkoutSetCell(workoutSet: workoutSet6, index: 6)
                WorkoutSetCell(workoutSet: workoutSet8, index: 7)
            }
        }
        .listStyleCompat_InsetGroupedListStyle()
        .mockEnvironment(weightUnit: .metric)
    }
}
#endif
