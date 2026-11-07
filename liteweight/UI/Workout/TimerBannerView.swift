//
//  TimerBannerView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 14.08.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct TimerBannerView: View {
    @EnvironmentObject var restTimerStore: RestTimerStore
    
    @ObservedObject var workout: Workout

    @ObservedObject private var refresher = Refresher()
    
    @State private var activeSheet: SheetType?

    private enum SheetType: Identifiable {
        case restTimer
        case editTime
        
        var id: Self { self }
    }

    private let workoutTimerDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    private var editTimeSheet: some View {
        LiteweightUtilitySheet(
            title: "Workout duration",
            subtitle: "Adjust the session clock",
            systemImage: "stopwatch",
            onClose: { activeSheet = nil }
        ) {
            EditCurrentWorkoutTimeView(workout: workout) {
                activeSheet = nil
            }
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)    }
    
    private var restTimerSheet: some View {
        LiteweightUtilitySheet(
            title: "Rest timer",
            subtitle: "Dial in your recovery",
            systemImage: "timer",
            onClose: { activeSheet = nil }
        ) {
            RestTimerView()
                .environmentObject(restTimerStore)
        }
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)    }
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                self.activeSheet = .editTime
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "stopwatch")
                        .foregroundColor(LiteweightTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(LiteweightTheme.secondaryText)
                        Text(workoutTimerDurationFormatter.string(from: workout.safeDuration) ?? "00:00")
                            .font(.liteweightMetric(.callout, weight: .semibold))
                            .foregroundColor(LiteweightTheme.primaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Capsule().fill(.regularMaterial))
            }
            .buttonStyle(.plain)

            Button(action: {
                self.activeSheet = .restTimer
            }) {
                let remainingTime = restTimerStore.restTimerRemainingTime
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundColor((remainingTime ?? 0) < 0 ? LiteweightTheme.danger : LiteweightTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(LiteweightTheme.secondaryText)
                        if let remainingTime = remainingTime {
                            Text(restTimerDurationFormatter.string(from: abs(remainingTime.rounded(.up))) ?? "00:00")
                                .font(.liteweightMetric(.callout, weight: .semibold))
                                .foregroundColor(remainingTime < 0 ? LiteweightTheme.danger : LiteweightTheme.primaryText)
                        } else {
                            Text("Start timer")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(LiteweightTheme.primaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Capsule().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LiteweightTheme.horizontalPadding)
        .padding(.vertical, 10)
        .background(Color(.systemBackground).overlay(Divider(), alignment: .bottom))
        .sheet(item: $activeSheet) { sheet in
            if sheet == .editTime {
                self.editTimeSheet
            } else if sheet == .restTimer {
                self.restTimerSheet
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in self.refresher.refresh() }
    }
}

#if DEBUG
struct TimerBannerView_Previews: PreviewProvider {
    static var previews: some View {
        if RestTimerStore.shared.restTimerRemainingTime == nil {
            RestTimerStore.shared.start(duration: 10)
        }
        return TimerBannerView(workout: MockWorkoutData.metricRandom.currentWorkout)
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
