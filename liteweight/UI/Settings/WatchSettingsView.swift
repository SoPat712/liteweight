//
//  WatchSettingsView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 12.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import UIKit
import WatchConnectivity

struct WatchSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var isRefreshing = false
    @State private var watchAppUnavailable = false
    /// Values shown while a refresh runs. WatchConnectivity reports in several quick steps
    /// (reachability especially flaps), so the page holds still and shows only the result.
    @State private var frozenStatus: WatchStatus?
    @State private var refreshToken = 0

    @ObservedObject private var connection = WatchConnectionManager.shared

    private struct WatchStatus: Equatable {
        let isPaired: Bool
        let isInstalled: Bool
        let isReachable: Bool
    }

    private var liveStatus: WatchStatus {
        WatchStatus(isPaired: connection.isPaired, isInstalled: connection.isWatchAppInstalled,
                    isReachable: connection.isReachable)
    }

    private var shownStatus: WatchStatus { frozenStatus ?? liveStatus }

    private enum ConnectionState {
        case unavailable
        case installRequired
        case ready

        var needsSetup: Bool { self != .ready }
    }

    /// Paired and installed decide readiness. Reachability only says whether the watch app
    /// is awake right now, so it stays in the Connection row instead of flipping the badge.
    private var connectionState: ConnectionState {
        guard shownStatus.isPaired else { return .unavailable }
        guard shownStatus.isInstalled else { return .installRequired }
        return .ready
    }

    private var isCompanionAvailable: Bool {
        !connectionState.needsSetup
    }

    private var displayedWatchCompanion: Bool {
        settingsStore.watchCompanion
    }

    private var watchCompanionBinding: Binding<Bool> {
        Binding(
            get: { displayedWatchCompanion },
            set: { settingsStore.watchCompanion = $0 }
        )
    }

    var body: some View {
        List {
            Section {
                SettingsConnectionHeader(title: "Apple Watch", systemImage: "applewatch", tint: LiteweightTheme.mediaBackdrop,
                                         status: statusTitle, isGood: !connectionState.needsSetup,
                                         detail: connectionState.needsSetup ? nil : "Paired and installed") {
                    if connectionState.needsSetup {
                        Button(action: openWatchSetup) {
                            Label(shownStatus.isPaired ? "Install liteweight on Watch" : "Pair in Watch App",
                                  systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity, minHeight: LiteweightTheme.controlHeight)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Opens the Watch app on this iPhone")
                    }
                }
            }

            // When everything works the header says so; the checks only appear to show what failed.
            if connectionState.needsSetup {
                Section {
                    LabeledContent {
                        statusValue(shownStatus.isPaired)
                    } label: {
                        SettingsRowLabel("Paired", systemImage: "applewatch.radiowaves.left.and.right", tint: LiteweightTheme.accent)
                    }
                    LabeledContent {
                        statusValue(shownStatus.isInstalled)
                    } label: {
                        SettingsRowLabel("liteweight Installed", systemImage: "app.badge.checkmark", tint: LiteweightTheme.metricVolume)
                    }
                } header: {
                    Text("Status")
                } footer: {
                    Text(shownStatus.isPaired
                         ? "In the Watch app, find liteweight under Available Apps and tap Install."
                         : "Open the Watch app on this iPhone and pair your Apple Watch.")
                }
            }

            Section {
                SettingsToggle("Start with iPhone Workouts", systemImage: "figure.strengthtraining.traditional",
                               tint: LiteweightTheme.accent, isOn: watchCompanionBinding)
                    .toggleStyle(.switch)
                    .tint(LiteweightTheme.accent)
                    .disabled(!isCompanionAvailable)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Start with iPhone Workouts")
                    .accessibilityValue(
                        isCompanionAvailable
                            ? (displayedWatchCompanion ? "On" : "Off")
                            : (displayedWatchCompanion ? "On, setup required" : "Off, setup required")
                    )
            } header: {
                Text("Workout Companion")
            } footer: {
                Text(companionDetail)
            }
        }
        .labeledContentStyle(SettingsValueStyle())
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 36)
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { refreshConnectionStatus(announce: true) } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel(isRefreshing ? "Checking watch status" : "Refresh Status")
                .disabled(isRefreshing)
            }
        }
        .animation(LiteweightMotion.preferred(LiteweightMotion.fade, reduceMotion: UIAccessibility.isReduceMotionEnabled),
                   value: connectionState.needsSetup)
        .liteweightScreen()
        .onAppear { refreshConnectionStatus(announce: false) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshConnectionStatus(announce: false)
        }
        .onChange(of: connection.connectionRevision) { _, _ in
            // Each report restarts a short settle window; the page updates once it's quiet.
            guard isRefreshing else { return }
            scheduleFinish(after: 1.0)
        }
        .alert("Could not open the Watch app", isPresented: $watchAppUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open the Watch app from your iPhone Home Screen to pair your watch or install liteweight.")
        }
    }

    private var statusTitle: String {
        switch connectionState {
        case .unavailable: return "Not Paired"
        case .installRequired: return "liteweight Not Installed"
        case .ready: return "Ready"
        }
    }

    private func statusValue(_ isOK: Bool) -> some View {
        Text(isOK ? "Yes" : "No")
            .foregroundStyle(isOK ? LiteweightTheme.secondaryText : LiteweightTheme.danger)
    }

    private var companionDetail: String {
        #if DEBUG
        if settingsStore.healthTestMode {
            return "Test mode: no heart rate, calories or Apple Health."
        }
        #endif
        if !isCompanionAvailable {
            return "Needs a paired Apple Watch with liteweight installed."
        }
        if displayedWatchCompanion {
            return "Apple Watch records heart rate and calories."
        }
        return "iPhone workouts won't start a Watch workout."
    }

    @State private var announcesRefresh = false

    private func refreshConnectionStatus(announce: Bool) {
        guard !isRefreshing else { return }
        frozenStatus = liveStatus
        announcesRefresh = announce
        isRefreshing = true
        connection.refreshConnectionStatus()
        scheduleFinish(after: 1.0)
        // An escape hatch for a broken or suspended WatchConnectivity service, so the
        // row can never stay busy forever.
        let token = refreshToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard isRefreshing, refreshToken == token else { return }
            finishRefresh()
        }
    }

    private func scheduleFinish(after delay: TimeInterval) {
        refreshToken += 1
        let token = refreshToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isRefreshing, refreshToken == token else { return }
            finishRefresh()
        }
    }

    private func finishRefresh() {
        withAnimation(LiteweightMotion.preferred(LiteweightMotion.fade, reduceMotion: UIAccessibility.isReduceMotionEnabled)) {
            frozenStatus = nil
            isRefreshing = false
        }
        guard announcesRefresh else { return }
        let status = liveStatus
        let toast: LiteweightToast
        if !status.isPaired {
            toast = LiteweightToast(title: "Watch Not Paired", subtitle: "Pair it in the Watch app",
                               systemImage: "applewatch.slash", style: .warning)
        } else if !status.isInstalled {
            toast = LiteweightToast(title: "liteweight Not on Watch", subtitle: "Install it from the Watch app",
                               systemImage: "exclamationmark.applewatch", style: .warning)
        } else {
            toast = LiteweightToast(title: "Apple Watch Ready",
                               subtitle: status.isReachable ? "Connection: Live" : "Connection: Standby",
                               systemImage: "checkmark.applewatch", style: .success)
        }
        LiteweightToastCenter.shared.show(toast)
    }

    private func openWatchSetup() {
        guard let watchURL = URL(string: "itms-watch://") else { return }
        UIApplication.shared.open(watchURL, options: [:]) { opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                watchAppUnavailable = true
            }
        }
    }
}

extension WatchSettingsView {
    static var isSupported: Bool {
        WCSession.isSupported()
    }
}

struct WatchSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WatchSettingsView()
                .environmentObject(SettingsStore.shared)
        }
    }
}
