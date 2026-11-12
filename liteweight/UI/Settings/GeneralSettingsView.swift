//
//  GeneralSettingsView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 31.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var expandedRest: RestPreference?

    private enum RestPreference {
        case standard, dumbbell, barbell

        var systemImage: String {
            switch self {
            case .standard: return "hourglass"
            case .dumbbell: return "dumbbell.fill"
            case .barbell: return "figure.strengthtraining.traditional"
            }
        }
    }

    var body: some View {
        Form {
            restSection
            loggingSection
            calculatorsSection
            duringWorkoutSection
        }
        .formStyle(.grouped)
        .labeledContentStyle(SettingsValueStyle())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 36)
        }
        .navigationTitle("Workout Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .liteweightScreen()
    }

    private var restSection: some View {
        Section {
            SettingsToggle("Auto-Start Rest Timer", systemImage: "timer", tint: LiteweightTheme.metricTime,
                           isOn: $settingsStore.autoStartRestTimer)
            restRow("Default", preference: .standard, selection: $settingsStore.defaultRestTime)
            restRow("Dumbbell Exercises", preference: .dumbbell, selection: $settingsStore.defaultRestTimeDumbbellBased)
            restRow("Barbell Exercises", preference: .barbell, selection: $settingsStore.defaultRestTimeBarbellBased)
            SettingsToggle("Count Past Zero", systemImage: "clock.arrow.circlepath", tint: LiteweightTheme.metricTime, isOn: Binding(
                get: { settingsStore.keepRestTimerRunning },
                set: { newValue in
                    settingsStore.keepRestTimerRunning = newValue
                    RestTimerStore.shared.notifyKeepRestTimerRunningChanged()
                }
            ))
        } header: {
            Text("Rest Timer")
        } footer: {
            Text("Count Past Zero shows overtime in red.")
        }
    }

    private var loggingSection: some View {
        Section {
            SettingsToggle("Log RPE", systemImage: "gauge.with.dots.needle.50percent", tint: LiteweightTheme.metricEffort,
                           isOn: $settingsStore.logRPE)
            SettingsToggle("Carry Over Last Values", systemImage: "arrow.clockwise", tint: LiteweightTheme.accent,
                           isOn: $settingsStore.prefillPreviousValues)
            SettingsToggle("Stopwatch for Timed Sets", systemImage: "stopwatch", tint: LiteweightTheme.metricTime,
                           isOn: $settingsStore.inlineSetTimer)
        } header: {
            Text("Logging")
        } footer: {
            Text("Carry Over fills in last time's weight and reps.")
        }
    }

    private var calculatorsSection: some View {
        Section {
            SettingsToggle("Plate Calculator", systemImage: "plusminus", tint: LiteweightTheme.metricVolume,
                           isOn: $settingsStore.showPlateCalculator)
            NavigationLink {
                AvailablePlatesSettingsView(unit: settingsStore.weightUnit)
            } label: {
                SettingsRowLabel("Available Plates", systemImage: "circle.grid.2x2.fill", tint: LiteweightTheme.metricVolume)
            }
            SettingsToggle("Warm-Up Calculator", systemImage: "flame.fill", tint: LiteweightTheme.metricSets,
                           isOn: $settingsStore.showWarmUpCalculator)
        } header: {
            Text("Calculators")
        }
    }

    private var duringWorkoutSection: some View {
        Section {
            SettingsToggle("Advance Through Supersets", systemImage: "link", tint: LiteweightTheme.accent,
                           isOn: $settingsStore.supersetAutoScroll)
            SettingsToggle("Keep Screen Awake", systemImage: "sun.max.fill", tint: LiteweightTheme.metricRecord,
                           isOn: $settingsStore.keepScreenAwakeDuringWorkout)
        } header: {
            Text("During a Workout")
        } footer: {
            Text("Keeping the screen awake uses more battery.")
        }
    }

    @ViewBuilder
    private func restRow(_ title: String, preference: RestPreference, selection: Binding<TimeInterval>) -> some View {
        Button {
            withAnimation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion)) {
                expandedRest = expandedRest == preference ? nil : preference
            }
        } label: {
            HStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        SettingsRowLabel(title, systemImage: preference.systemImage, tint: LiteweightTheme.metricTime)
                        restValue(selection.wrappedValue)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SettingsRowLabel(title, systemImage: preference.systemImage, tint: LiteweightTheme.metricTime)
                    restValue(selection.wrappedValue)
                }
                Image(systemName: expandedRest == preference ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .accessibilityHidden(true)
            }
            // The List supplies the row height; matching the switch rows keeps one rhythm.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.automatic)
        .accessibilityLabel(title)
        .accessibilityValue(restTitle(selection.wrappedValue))
        .accessibilityHint(expandedRest == preference ? "Collapse rest length control" : "Expand rest length control")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection.wrappedValue = min(600, selection.wrappedValue + 15)
            case .decrement: selection.wrappedValue = max(30, selection.wrappedValue - 15)
            default: break
            }
        }

        if expandedRest == preference {
            // The ruler scrubs locally and persists only after the selection is committed.
            RestLengthRuler(
                value: Binding(get: { selection.wrappedValue }, set: { _ in }),
                range: 30...600,
                step: 15
            ) { selection.wrappedValue = $0 }
            .accessibilityLabel("\(title) rest length")
            .transition(.opacity)
        }
    }

    private func restValue(_ duration: TimeInterval) -> some View {
        Text(restTitle(duration))
            .font(.liteweightMetric(.body, weight: .semibold))
            .foregroundStyle(LiteweightTheme.metricTime)
            .fixedSize()
    }

    private func restTitle(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

struct AvailablePlatesSettingsView: View {
    let unit: WeightUnit
    @State private var inventory = PlateInventory.load()
    @State private var selectionFeedback = 0

    var body: some View {
        Form {
            Section {
                ForEach(PlateInventory.availablePlates(for: unit.plateLoadUnit), id: \.self) { weight in
                    let weightTitle = Text(weight.formatted()).font(.liteweightMetric(.body, weight: .semibold))
                    let unitTitle = Text(unit.unit.symbol).font(.footnote).foregroundColor(LiteweightTheme.secondaryText)
                    SettingsToggle(Text("\(weightTitle) \(unitTitle)"), isOn: Binding(
                        get: { inventory.isEnabled(weight, unit: unit.plateLoadUnit) },
                        set: {
                            guard inventory.isEnabled(weight, unit: unit.plateLoadUnit) != $0 else { return }
                            inventory.setEnabled($0, weight: weight, unit: unit.plateLoadUnit)
                            selectionFeedback += 1
                        }
                    ))
                    .accessibilityLabel("\(weight.formatted()) \(unit.unit.symbol) plates")
                }
            } header: {
                Text("Available Plates · \(unit.unit.symbol)")
            } footer: {
                Text(inventory.enabledPlates(for: unit.plateLoadUnit).isEmpty
                     ? "No plates on: only the bar or machine weight loads."
                     : "Each plate that's on counts as unlimited.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 36)
        }
        .navigationTitle("Available Plates")
        .navigationBarTitleDisplayMode(.inline)
        .liteweightScreen()
        .onAppear { inventory = .load() }
        .onChange(of: inventory) { inventory.save() }
        .sensoryFeedback(.selection, trigger: selectionFeedback) { _, _ in SettingsStore.shared.workoutHaptics }
    }
}

/// The weight unit lives on the Settings list itself; a page holding one switch was a dead end.
struct WeightUnitSettingsRow<Icon: View>: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: Icon

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            HStack(spacing: 14) {
                icon
                Text("Weight Unit")
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            // A switch-height blue thumb, like the switches beside it; the large system
            // segmented control was taller than the row's title and gray when chosen.
            LiteweightSegmentedPicker(title: "Weight Unit", selection: Binding(
                get: { settingsStore.weightUnit },
                set: {
                    guard settingsStore.weightUnit != $0 else { return }
                    settingsStore.weightUnit = $0
                }
            ), segments: [
                .init(value: WeightUnit.metric, title: "kg", accessibilityLabel: "Kilograms"),
                .init(value: WeightUnit.imperial, title: "lb", accessibilityLabel: "Pounds")
            ])
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 104)
        }
        .font(.body)
        .foregroundStyle(LiteweightTheme.primaryText)
    }
}

struct SoundsSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing: LiteweightSoundPlayer.Sound?
    @State private var playToken = 0
    @State private var previewed: LiteweightSoundPlayer.Sound = .tick
    @State private var hapticTrigger = 0

    var body: some View {
        Form {
            Section {
                SettingsToggle("Sound Effects", systemImage: "speaker.wave.2.fill", tint: LiteweightTheme.metricEffort,
                               isOn: $settingsStore.workoutSounds)
                SettingsToggle("Haptics", systemImage: "hand.tap.fill", tint: LiteweightTheme.metricEffort,
                               isOn: $settingsStore.workoutHaptics)
                SettingsToggle("Personal Record Alerts", systemImage: "trophy.fill", tint: LiteweightTheme.metricRecord,
                               isOn: $settingsStore.personalRecordAlerts)
            } header: {
                Text("Feedback")
            } footer: {
                Text("During workouts, sounds follow your ringer switch and mix with music.")
            }
            Section {
                ForEach(LiteweightSoundPlayer.Sound.allCases) { sound in
                    Button { preview(sound) } label: {
                        HStack(spacing: 12) {
                            SettingsRowLabel(sound.title, systemImage: sound.settingsSymbol, tint: sound.settingsTint)
                            previewIndicator(isPlaying: playing == sound)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Play \(sound.title)")
                    .disabled(!settingsStore.workoutSounds && !settingsStore.workoutHaptics)
                }
            } header: {
                Text("Try Them")
            } footer: {
                Text("Previews play even when your ringer is off.")
            }
        }
        .sensoryFeedback(trigger: hapticTrigger) { _, _ in
            settingsStore.workoutHaptics ? previewed.previewFeedback : nil
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 36)
        }
        .navigationTitle("Sounds & Haptics")
        .navigationBarTitleDisplayMode(.inline)
        .liteweightScreen()
    }

    /// A filled play button that turns into animated sound waves while the preview plays.
    private func previewIndicator(isPlaying: Bool) -> some View {
        Image(systemName: isPlaying ? "speaker.wave.3.fill" : "play.fill")
            .font(.footnote.weight(.bold))
            .foregroundStyle(LiteweightTheme.onAccent)
            .symbolEffect(.variableColor.iterative, isActive: isPlaying && !reduceMotion)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 32, height: 32)
            .background(LiteweightTheme.accent, in: Circle())
            .accessibilityHidden(true)
    }

    private func preview(_ sound: LiteweightSoundPlayer.Sound) {
        LiteweightSoundPlayer.shared.play(sound, preview: true)
        previewed = sound
        hapticTrigger += 1
        playToken += 1
        let token = playToken
        withAnimation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion)) { playing = sound }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard playToken == token else { return }
            withAnimation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion)) { playing = nil }
        }
    }
}

private extension LiteweightSoundPlayer.Sound {
    var settingsSymbol: String {
        switch self {
        case .setComplete: return "checkmark"
        case .setRecord: return "trophy.fill"
        case .tick: return "hand.tap.fill"
        case .restComplete: return "timer"
        case .workoutFinish: return "flag.checkered"
        }
    }

    var settingsTint: Color {
        switch self {
        case .setComplete: return LiteweightTheme.accent
        case .setRecord: return LiteweightTheme.metricRecord
        case .tick: return LiteweightTheme.metricEffort
        case .restComplete: return LiteweightTheme.metricTime
        case .workoutFinish: return LiteweightTheme.metricVolume
        }
    }

    /// The phone haptic that accompanies each cue, mirroring the Watch's choices.
    var previewFeedback: SensoryFeedback {
        switch self {
        case .setComplete, .workoutFinish: return .success
        case .setRecord: return .increase
        case .tick: return .selection
        case .restComplete: return .impact(weight: .heavy)
        }
    }
}

/// The colored symbol tile from the main Settings list. Every Settings row carries one,
/// so each setting reads as a thing you can change rather than a line of text.
struct SettingsRowIcon: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30
    let systemImage: String
    var tint: Color = LiteweightTheme.accent

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(LiteweightTheme.outline, lineWidth: 1)
            }
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(LiteweightTheme.onAccent)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Icon tile and title, for navigation rows and rows with a trailing control.
struct SettingsRowLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: Text
    let systemImage: String
    var tint: Color = LiteweightTheme.accent

    init(_ title: String, systemImage: String, tint: Color = LiteweightTheme.accent) {
        self.init(Text(title), systemImage: systemImage, tint: tint)
    }

    init(_ title: Text, systemImage: String, tint: Color = LiteweightTheme.accent) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
                .opacity(isEnabled ? 1 : 0.5)
            title
                .foregroundStyle(isEnabled ? LiteweightTheme.primaryText : LiteweightTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A native switch with room for its title to wrap beside it.
struct SettingsToggle: View {
    @Environment(\.isEnabled) private var isEnabled
    private let title: Text
    private let systemImage: String?
    private let tint: Color
    @Binding private var isOn: Bool

    init(_ title: String, systemImage: String? = nil, tint: Color = LiteweightTheme.accent, isOn: Binding<Bool>) {
        self.init(Text(title), systemImage: systemImage, tint: tint, isOn: isOn)
    }

    // Plate labels retain their metric numerals and secondary units.
    init(_ title: Text, systemImage: String? = nil, tint: Color = LiteweightTheme.accent, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self._isOn = isOn
    }

    var body: some View {
        // At large text a Toggle with a text-only label moves its switch below the title.
        // A bare switch beside the title can't stack; VoiceOver still gets one native switch.
        HStack(spacing: 12) {
            if let systemImage {
                SettingsRowLabel(title, systemImage: systemImage, tint: tint)
            } else {
                title
                    .foregroundStyle(isEnabled ? LiteweightTheme.primaryText : LiteweightTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $isOn) { title }
                .labelsHidden()
        }
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { title }
        }
    }
}

/// An action row: icon tile, title, and a trailing symbol for what the tap does, which
/// becomes a spinner while the action works. Keeps the native row highlight.
struct SettingsActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var systemImage: String?
    var tint: Color
    var trailingSymbol: String?
    var isPreparing = false

    init(_ title: String, systemImage: String? = nil, tint: Color = LiteweightTheme.accent,
         trailingSymbol: String? = nil, isPreparing: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.trailingSymbol = trailingSymbol
        self.isPreparing = isPreparing
    }

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                SettingsRowLabel(isPreparing ? "Preparing…" : title, systemImage: systemImage, tint: tint)
            } else {
                Text(isPreparing ? "Preparing…" : title)
                    .foregroundStyle((isPreparing || !isEnabled) ? LiteweightTheme.secondaryText : LiteweightTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if isPreparing {
                ProgressView()
                    .controlSize(.small)
                    .tint(LiteweightTheme.secondaryText)
                    .accessibilityHidden(true)
            } else if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isEnabled ? LiteweightTheme.accent : LiteweightTheme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A colored symbol and word for a connection's state: green check or red exclamation.
struct SettingsStatusBadge: View {
    let text: String
    let isGood: Bool

    var body: some View {
        let tint = isGood ? LiteweightTheme.success : LiteweightTheme.danger
        // Not a Label: inside List rows the list restyles Labels into its icon column.
        HStack(spacing: 5) {
            Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// The top of a connection page (Apple Health, Apple Watch): a large icon, the name,
/// a status badge with one line of detail, and the one action that matters now as a
/// real button. The detail line replaces rows of "Yes" when everything works.
struct SettingsConnectionHeader<Action: View>: View {
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 56
    let title: String
    let systemImage: String
    let tint: Color
    let status: String
    let isGood: Bool
    var detail: String? = nil
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                    .fill(tint)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: iconSize * 0.5, weight: .semibold))
                            .foregroundStyle(LiteweightTheme.onAccent)
                    }
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(LiteweightTheme.primaryText)
                    SettingsStatusBadge(text: status, isGood: isGood)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(LiteweightTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            action()
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
    }
}

/// Keep native label/value semantics while allowing both columns to wrap at large text sizes.
struct SettingsValueStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                configuration.label
                configuration.content.foregroundStyle(LiteweightTheme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                configuration.label.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                configuration.content
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            GeneralSettingsView()
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
