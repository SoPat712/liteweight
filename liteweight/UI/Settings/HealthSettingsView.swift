//
//  HealthSettingsView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 31.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import UIKit
import CoreData
import HealthKit
import WorkoutDataKit

/// Apple Health is informational (build 119): the connection, what liteweight saves in each
/// category, and the workouts it has saved. Workouts save as they finish and waiting ones retry
/// on their own; a single workout can still be synced from its detail page.
struct HealthSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @EnvironmentObject var settingsStore: SettingsStore
    #endif

    @FetchRequest(fetchRequest: HealthSettingsView.savedWorkoutsRequest) private var savedWorkouts: FetchedResults<Workout>
    @FetchRequest(fetchRequest: HealthSettingsView.waitingWorkoutsRequest) private var waitingWorkouts: FetchedResults<Workout>

    @State private var authorizing = false
    @State private var accessState = HealthManager.AccessState.notDetermined
    @State private var categories: [HealthManager.SaveCategory] = []
    @State private var activeModal: HealthModal?

    private struct HealthModal: Identifiable {
        enum Kind {
            case accessFailed(Error)
            case healthAppUnavailable
        }

        let id = UUID()
        let kind: Kind
    }

    /// Workouts in Apple Health: saved by the phone, or recorded there directly by the Watch.
    static var savedWorkoutsRequest: NSFetchRequest<Workout> {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "isCurrentWorkout == NO AND healthExportState IN %@", ["exported", "watch"])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
        return request
    }

    private static var waitingWorkoutsRequest: NSFetchRequest<Workout> {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "isCurrentWorkout == NO AND healthExportState == %@", "pending")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
        return request
    }

    private var isConnectable: Bool { accessState != .unavailable && accessState != .notDetermined }

    var body: some View {
        List {
            Section {
                SettingsConnectionHeader(title: "Apple Health", systemImage: "heart.fill", tint: LiteweightTheme.metricEffort,
                                         status: accessState.connectionTitle,
                                         isGood: accessState == .ready,
                                         detail: accessState.connectionDetail) {
                    if accessState == .notDetermined {
                        Button(action: requestAccess) {
                            HStack(spacing: 8) {
                                if authorizing { ProgressView().controlSize(.small).tint(LiteweightTheme.onAccent) }
                                Text(authorizing ? "Connecting…" : "Connect Apple Health")
                            }
                            .frame(maxWidth: .infinity, minHeight: LiteweightTheme.controlHeight)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(authorizing ? "Requesting Apple Health access" : "Connect Apple Health")
                        .disabled(authorizing)
                    }
                }
            }

            if isConnectable {
                categoriesSection
            }

            if isConnectable || !savedWorkouts.isEmpty {
                savedSection
            }

            #if DEBUG
            Section {
                SettingsToggle("Don't Record to Apple Health", systemImage: "testtube.2", tint: LiteweightTheme.secondaryText,
                               isOn: $settingsStore.healthTestMode)
                    .toggleStyle(.switch)
                    .tint(LiteweightTheme.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Don't Record to Apple Health")
                    .accessibilityValue(settingsStore.healthTestMode ? "On" : "Off")
            } header: {
                Text("Testing")
            } footer: {
                Text("Skips heart rate, calories and Health, so rings don’t move.")
            }
            #endif
        }
        .labeledContentStyle(SettingsValueStyle())
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 36)
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .liteweightScreen()
        .onAppear(perform: refreshAccessState)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshAccessState()
        }
        .sheet(item: $activeModal) { modal in
            switch modal.kind {
            case .accessFailed(let error):
                LiteweightStatusSheet(
                    headerTitle: "Apple Health",
                    title: "Could not connect",
                    message: error.localizedDescription,
                    systemImage: "heart.slash.fill",
                    tint: LiteweightTheme.danger
                )
            case .healthAppUnavailable:
                LiteweightStatusSheet(
                    headerTitle: "Apple Health",
                    title: "Could not open Health",
                    message: "Open the Health app manually, tap your profile, then review Apps and Services → liteweight.",
                    systemImage: "arrow.up.forward.app.fill",
                    tint: LiteweightTheme.warning
                )
            }
        }
    }

    /// One row per category with Health's answer; categories never asked for can be asked again.
    private var categoriesSection: some View {
        Section {
            ForEach(categories) { category in
                LabeledContent {
                    category.statusLabel
                } label: {
                    SettingsRowLabel(category.kind.title, systemImage: category.kind.systemImage, tint: category.kind.tint)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(category.kind.title)
                .accessibilityValue(category.statusText)
            }
            if categories.contains(where: { $0.status == .notDetermined }) {
                Button(action: requestAccess) {
                    SettingsActionLabel("Ask for Missing Categories", systemImage: "plus", tint: LiteweightTheme.metricEffort,
                                        isPreparing: authorizing)
                }
                .disabled(authorizing)
            }
            Button(action: openHealthApp) {
                SettingsActionLabel("Manage in Health", systemImage: "arrow.up.forward.app", tint: LiteweightTheme.metricEffort,
                                    trailingSymbol: "arrow.up.forward")
            }
        } header: {
            Text("What liteweight Saves")
        } footer: {
            Text("Change these in Health. Apple doesn't let apps see what they can read, so reading isn't listed.")
        }
    }

    private var savedSection: some View {
        Section {
            if savedWorkouts.isEmpty {
                Text("Workouts you finish appear here once they're saved to Health.")
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
            } else {
                ForEach(Array(savedWorkouts.prefix(5)), id: \.objectID) { workout in
                    HealthSavedWorkoutRow(workout: workout)
                }
                if savedWorkouts.count > 5 {
                    NavigationLink {
                        HealthSavedWorkoutsView()
                    } label: {
                        LabeledContent("Show All", value: "\(savedWorkouts.count)")
                    }
                }
            }
            if !waitingWorkouts.isEmpty {
                SettingsRowLabel("\(waitingWorkouts.count) waiting to save", systemImage: "hourglass",
                                 tint: LiteweightTheme.secondaryText)
                    .accessibilityHint("Saves on its own once Health can take it")
            }
        } header: {
            Text("Saved to Health")
        } footer: {
            Text("Imported workouts are never sent to Apple Health.")
        }
    }

    private func openHealthApp() {
        guard let healthURL = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(healthURL, options: [:]) { opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                activeModal = HealthModal(kind: .healthAppUnavailable)
            }
        }
    }

    private func refreshAccessState() {
        accessState = HealthManager.shared.accessState
        categories = HealthManager.shared.saveCategories
    }

    /// The system sheet is the confirmation; the rows update in place, so only a failure gets a sheet.
    private func requestAccess() {
        guard !authorizing else { return }
        authorizing = true
        HealthManager.shared.requestWorkoutAndBodyMeasurementPermission { result in
            DispatchQueue.main.async {
                authorizing = false
                refreshAccessState()
                if case .failure(let error) = result {
                    activeModal = HealthModal(kind: .accessFailed(error))
                }
            }
        }
    }
}

/// Every workout liteweight has saved to Apple Health, newest first (build 119).
struct HealthSavedWorkoutsView: View {
    @FetchRequest(fetchRequest: HealthSettingsView.savedWorkoutsRequest) private var workouts: FetchedResults<Workout>

    var body: some View {
        List {
            Section {
                ForEach(workouts, id: \.objectID) { workout in
                    HealthSavedWorkoutRow(workout: workout)
                }
            } footer: {
                Text("^[\(workouts.count) workout](inflect: true) saved to Apple Health.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Saved to Health")
        .navigationBarTitleDisplayMode(.inline)
        .liteweightScreen()
    }
}

/// A saved workout that opens its detail; the Watch symbol marks ones the Watch recorded into Health.
private struct HealthSavedWorkoutRow: View {
    @ObservedObject var workout: Workout

    var body: some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            HStack(spacing: 12) {
                CalendarWorkoutRow(workout: workout, showsDate: true)
                Spacer(minLength: 0)
                if workout.healthExportState == "watch" {
                    Image(systemName: "applewatch")
                        .foregroundStyle(LiteweightTheme.secondaryText)
                        .accessibilityLabel("Recorded on Apple Watch")
                }
            }
        }
    }
}

private extension HealthManager.SaveCategory.Kind {
    var title: String {
        switch self {
        case .workouts: return "Workouts"
        case .bodyWeight: return "Body Weight"
        case .height: return "Height"
        case .bodyFat: return "Body Fat"
        case .waist: return "Waist"
        case .effort: return "Workout Effort"
        }
    }

    var systemImage: String {
        switch self {
        case .workouts: return "figure.strengthtraining.traditional"
        case .bodyWeight: return "scalemass.fill"
        case .height: return "ruler.fill"
        case .bodyFat: return "percent"
        case .waist: return "lines.measurement.horizontal"
        case .effort: return "flame.fill"
        }
    }

    var tint: Color {
        switch self {
        case .workouts: return LiteweightTheme.accent
        case .effort: return LiteweightTheme.metricEffort
        default: return LiteweightTheme.metricBody
        }
    }
}

private extension HealthManager.SaveCategory {
    var statusText: String {
        switch status {
        case .sharingAuthorized: return "Saving"
        case .sharingDenied: return "Off"
        default: return "Not Asked"
        }
    }

    @ViewBuilder
    var statusLabel: some View {
        if status == .sharingAuthorized {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(statusText)
            }
            .foregroundStyle(LiteweightTheme.success)
        } else {
            Text(statusText)
                .foregroundStyle(LiteweightTheme.secondaryText)
        }
    }
}

private extension HealthManager.AccessState {
    var connectionTitle: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .notDetermined: return "Not Connected"
        case .workoutsOff: return "Not Saving Workouts"
        case .ready: return "Connected"
        }
    }

    /// The connection and what it shares, in one line under the badge.
    var connectionDetail: String {
        switch self {
        case .unavailable: return "Apple Health isn't available on this device."
        case .notDetermined: return "Connect to save workouts and sync body measurements."
        case .workoutsOff: return "Workouts are off in Health, so finished workouts aren't saved there."
        case .ready: return "Workouts save to Health when you finish."
        }
    }
}

extension HealthSettingsView {
    static var isSupported: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
}

struct HealthSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        HealthSettingsView()
    }
}
