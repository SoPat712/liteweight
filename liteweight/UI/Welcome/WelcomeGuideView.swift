//
//  WelcomeGuideView.swift
//  liteweight
//
//  The first-launch welcome: what liteweight does, the weight unit, how to start,
//  starter plans, Apple Health and Apple Watch. One page at a time; every page
//  after the first has Back and Skip.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import WorkoutDataKit

struct WelcomeGuideView: View {
    enum Page: Hashable { case unit, start, plans, health, watch }

    let mode: WelcomeGuideController.Mode
    let onFinish: () -> Void

    @State private var path: [Page] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeIntroPage { advance(from: nil) }
                .navigationDestination(for: Page.self) { page in
                    destination(page)
                        .toolbar {
                            if page != .watch {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Skip", action: onFinish)
                                        .accessibilityHint("Closes the welcome. You can replay it in Settings.")
                                }
                            }
                        }
                }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func destination(_ page: Page) -> some View {
        switch page {
        case .unit: WelcomeUnitPage { advance(from: .unit) }
        case .start: WelcomeStartPage(onPlans: { path.append(.plans) }, onContinue: { advance(from: .start) })
        case .plans: WelcomePlansPage { advance(from: .plans) }
        case .health: WelcomeHealthPage { advance(from: .health) }
        case .watch: WelcomeWatchPage(onFinish: onFinish)
        }
    }

    /// The page after `page` (nil is the welcome page) that applies to this person.
    private func next(after page: Page?) -> Page? {
        let order: [Page] = mode == .full ? [.unit, .start, .health, .watch] : [.health, .watch]
        var start = 0
        if let page {
            // Starter plans branch off how-to-start and rejoin after it.
            let anchor = page == .plans ? Page.start : page
            start = (order.firstIndex(of: anchor) ?? order.count - 1) + 1
        }
        return order.dropFirst(start).first(where: includes)
    }

    private func includes(_ page: Page) -> Bool {
        switch page {
        case .unit, .start, .plans: return true
        case .health:
            let state = HealthManager.shared.accessState
            return state != .unavailable && (mode == .full || state != .ready)
        case .watch:
            return WatchConnectionManager.shared.isPaired
        }
    }

    private func advance(from page: Page?) {
        if let next = next(after: page) {
            path.append(next)
        } else {
            onFinish()
        }
    }
}

// MARK: - Layout

/// A scrolling page with its actions pinned at the bottom, so large text never
/// pushes Continue off the screen.
private struct WelcomePageLayout<Content: View, Actions: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        let page = ScrollView {
            VStack(spacing: 24) { content }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        Group {
            if Actions.self == EmptyView.self {
                page
            } else {
                page.safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 10) { actions }
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(LiteweightTheme.background)
                }
            }
        }
        .background(LiteweightTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WelcomeTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(LiteweightTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(LiteweightTheme.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A rounded symbol tile above a page title.
private struct WelcomeHeroIcon: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64
    let systemImage: String
    let glyph: Color
    let fill: Color

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(fill)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(glyph)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct WelcomePrimaryButton: View {
    let title: String
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking { ProgressView().tint(LiteweightTheme.onAccent) }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(isWorking)
    }
}

private struct WelcomeSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: LiteweightTheme.controlHeight)
            .contentShape(Rectangle())
    }
}

// MARK: - G1 Welcome

private struct WelcomeIntroPage: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 76
    let onContinue: () -> Void

    var body: some View {
        WelcomePageLayout {
            RoundedRectangle(cornerRadius: iconSize * 0.25, style: .continuous)
                .fill(LinearGradient(colors: [LiteweightTheme.accent.opacity(0.78), LiteweightTheme.accent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: iconSize * 0.46, weight: .semibold))
                        .foregroundStyle(LiteweightTheme.onAccent)
                }
                .frame(width: iconSize, height: iconSize)
                .padding(.top, 16)
                .accessibilityHidden(true)

            WelcomeTitle(title: "Welcome to liteweight")

            VStack(alignment: .leading, spacing: 22) {
                feature("dumbbell.fill", "Log a set in one tap",
                        "Weight and reps come from last time. Change them if you need to, then log.")
                feature("timer", "Rest starts on its own",
                        "The timer runs under the set you logged, and on your Lock Screen.")
                feature("applewatch", "Train from your wrist",
                        "Log on Apple Watch. Your iPhone keeps up.")
                feature("chart.bar.fill", "See every muscle's week",
                        "Home shows what you trained and what's rested.")
            }
            .padding(.top, 8)
        } actions: {
            WelcomePrimaryButton(title: "Continue", action: onContinue)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(LiteweightTheme.accent)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(LiteweightTheme.primaryText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - G2 Weight unit

private struct WelcomeUnitPage: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onContinue: () -> Void

    var body: some View {
        WelcomePageLayout {
            WelcomeHeroIcon(systemImage: "scalemass.fill", glyph: LiteweightTheme.metricSets,
                            fill: LiteweightTheme.metricSetsContainer)
            WelcomeTitle(title: "Kilograms or pounds?",
                         subtitle: "liteweight uses it for every weight, chart and plate.")
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                unitCard(.metric, symbol: "kg", name: "Kilograms", example: "20 kg bar")
                unitCard(.imperial, symbol: "lb", name: "Pounds", example: "45 lb bar")
            }
        } actions: {
            Text("You can change this in Settings.")
                .font(.footnote)
                .foregroundStyle(LiteweightTheme.secondaryText)
            WelcomePrimaryButton(title: "Continue", action: onContinue)
        }
        .sensoryFeedback(.selection, trigger: settingsStore.weightUnit) { _, _ in settingsStore.workoutHaptics }
    }

    private func unitCard(_ unit: WeightUnit, symbol: String, name: String, example: String) -> some View {
        let isSelected = settingsStore.weightUnit == unit
        return Button {
            withAnimation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion)) {
                settingsStore.weightUnit = unit
            }
        } label: {
            VStack(spacing: 6) {
                Text(symbol)
                    .font(.liteweightMetric(.largeTitle))
                    .foregroundStyle(LiteweightTheme.primaryText)
                Text(name)
                    .font(.headline)
                    .foregroundStyle(LiteweightTheme.primaryText)
                Text(example)
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? LiteweightTheme.accent : LiteweightTheme.tertiaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(LiteweightTheme.surface,
                        in: RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? LiteweightTheme.accent : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(example)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - G3 How to start

private struct WelcomeStartPage: View {
    private enum FileKind { case hevy, backup }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var fileKind: FileKind?
    @State private var fileError: String?
    let onPlans: () -> Void
    let onContinue: () -> Void

    private static let backupTypes: [UTType] = LiteweightBackup.acceptedBackupTypeIdentifiers
        .compactMap { UTType($0) } + [.json]

    var body: some View {
        WelcomePageLayout {
            WelcomeTitle(title: "How do you want to start?", subtitle: "You can do any of these later.")
                .padding(.top, 16)
            VStack(spacing: 0) {
                row("list.bullet.clipboard", tint: LiteweightTheme.accent, title: "Use a starter plan",
                    detail: "Ready-made workouts for 3 or 4 days a week.", action: onPlans)
                Divider().padding(.leading, 60)
                row("square.and.arrow.down", tint: LiteweightTheme.metricBody, title: "Import from Hevy",
                    detail: "Bring your history from a Hevy CSV export.") { fileKind = .hevy }
                Divider().padding(.leading, 60)
                row("arrow.counterclockwise", tint: LiteweightTheme.metricVolume, title: "Restore a backup",
                    detail: "Open a .liteweightbackup file.") { fileKind = .backup }
                Divider().padding(.leading, 60)
                row("plus", tint: LiteweightTheme.secondaryText, title: "Start from scratch",
                    detail: "Build workouts as you go.", action: onContinue)
            }
            .background(LiteweightTheme.surface,
                        in: RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous))
        } actions: {
            EmptyView()
        }
        .fileImporter(
            isPresented: Binding(get: { fileKind != nil }, set: { if !$0 { fileKind = nil } }),
            allowedContentTypes: fileKind == .backup ? Self.backupTypes : [.commaSeparatedText],
            allowsMultipleSelection: fileKind == .hevy
        ) { result in
            let kind = fileKind
            fileKind = nil
            pickedFiles(result, kind: kind)
        }
        .alert("File Not Opened", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("OK", role: .cancel) { fileError = nil }
        } message: {
            Text(fileError ?? "Please try again.")
        }
    }

    /// The files open after the welcome closes, through the same import and
    /// restore paths as a file opened from Files.
    private func pickedFiles(_ result: Result<[URL], Error>, kind: FileKind?) {
        do {
            let urls = try result.get()
            guard let kind, !urls.isEmpty else { return }
            let documents = try urls.map { url -> Data in
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url)
            }
            switch kind {
            case .hevy: WelcomeGuideController.shared.queueHevyImport(documents)
            case .backup: WelcomeGuideController.shared.queueRestore(documents[0])
            }
            onContinue()
        } catch {
            if (error as NSError).code == NSUserCancelledError { return }
            fileError = error.localizedDescription
        }
    }

    private func row(_ symbol: String, tint: Color, title: String, detail: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(LiteweightTheme.onAccent)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(LiteweightTheme.primaryText)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(LiteweightTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LiteweightTheme.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: LiteweightTheme.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - G4 Starter plans

private struct WelcomePlansPage: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var selection = StarterPlan.all[0]
    @State private var addError: String?
    @State private var addedFeedback = 0
    let onContinue: () -> Void

    var body: some View {
        let catalog = StarterPlan.catalogByTitle(exerciseStore)
        WelcomePageLayout {
            WelcomeTitle(title: "Pick a plan").padding(.top, 8)
            VStack(spacing: 12) {
                ForEach(StarterPlan.all) { plan in planCard(plan, catalog: catalog) }
            }
        } actions: {
            Text("Adds \(selection.days.count) saved workouts. Edit them any time on the Workout tab.")
                .font(.footnote)
                .foregroundStyle(LiteweightTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            WelcomePrimaryButton(title: "Add \(selection.name)", action: add)
        }
        .sensoryFeedback(.success, trigger: addedFeedback) { _, _ in settingsStore.workoutHaptics }
        .alert("Plan Not Added", isPresented: Binding(get: { addError != nil }, set: { if !$0 { addError = nil } })) {
            Button("OK", role: .cancel) { addError = nil }
        } message: {
            Text(addError ?? "Please try again.")
        }
    }

    private func add() {
        do {
            try selection.install(into: managedObjectContext, exerciseStore: exerciseStore)
            addedFeedback += 1
            onContinue()
        } catch {
            addError = error.localizedDescription
        }
    }

    private func planCard(_ plan: StarterPlan, catalog: [String: Exercise]) -> some View {
        let isSelected = plan == selection
        return Button {
            withAnimation(LiteweightMotion.preferred(LiteweightMotion.collapse, reduceMotion: reduceMotion)) {
                selection = plan
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(plan.name).font(.headline)
                        Spacer(minLength: 8)
                        Text(plan.frequency).font(.subheadline).foregroundStyle(LiteweightTheme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name).font(.headline)
                        Text(plan.frequency).font(.subheadline).foregroundStyle(LiteweightTheme.secondaryText)
                    }
                }
                .foregroundStyle(LiteweightTheme.primaryText)
                Text(plan.detail)
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                LiteweightChipFlow(spacing: 5) {
                    ForEach(Array(plan.muscleGroups(in: catalog).prefix(4)), id: \.self) {
                        LiteweightMuscleChip(group: $0)
                    }
                }
                if isSelected {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.days, id: \.title) { day in
                            (Text(day.title).foregroundColor(LiteweightTheme.primaryText).fontWeight(.semibold)
                             + Text(" · " + day.exercises.compactMap { catalog[$0]?.title }.joined(separator: ", "))
                                .foregroundColor(LiteweightTheme.secondaryText))
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(LiteweightTheme.surface,
                        in: RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? LiteweightTheme.accent : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: LiteweightTheme.heroCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - G5 Apple Health

private struct WelcomeHealthPage: View {
    @State private var isConnecting = false
    @State private var accessState = HealthManager.shared.accessState
    let onContinue: () -> Void

    var body: some View {
        WelcomePageLayout {
            WelcomeHeroIcon(systemImage: "heart.fill", glyph: LiteweightTheme.metricEffort,
                            fill: LiteweightTheme.diagramCanvas)
                .padding(.top, 16)
            WelcomeTitle(
                title: "Save workouts to Apple Health",
                subtitle: accessState == .ready
                    ? "Apple Health is connected. Each workout you finish in liteweight is saved there. Workouts you import stay out of Health."
                    : "Each workout you finish in liteweight is saved to Health, so it counts toward your rings. Workouts you import stay out of Health."
            )
        } actions: {
            if accessState == .ready {
                WelcomePrimaryButton(title: "Continue", action: onContinue)
            } else {
                WelcomePrimaryButton(title: isConnecting ? "Connecting…" : "Connect Apple Health",
                                     isWorking: isConnecting, action: connect)
                WelcomeSecondaryButton(title: "Not Now", action: onContinue)
            }
        }
    }

    /// The same request Settings › Apple Health makes. Either answer moves on;
    /// Settings can connect later.
    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        HealthManager.shared.requestWorkoutAndBodyMeasurementPermission { _ in
            DispatchQueue.main.async {
                isConnecting = false
                accessState = HealthManager.shared.accessState
                onContinue()
            }
        }
    }
}

// MARK: - G6 Apple Watch

private struct WelcomeWatchPage: View {
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 72
    let onFinish: () -> Void

    private var isInstalled: Bool { WatchConnectionManager.shared.isWatchAppInstalled }

    var body: some View {
        WelcomePageLayout {
            Image(systemName: "applewatch")
                .font(.system(size: symbolSize, weight: .regular))
                .foregroundStyle(LiteweightTheme.primaryText)
                .padding(.top, 16)
                .accessibilityHidden(true)
            WelcomeTitle(
                title: isInstalled ? "liteweight is on your Apple Watch" : "Add liteweight to your Apple Watch",
                subtitle: isInstalled
                    ? "Start a workout on either one and it opens on both. Turn the Digital Crown to change weight or reps."
                    : "Open the Watch app on your iPhone, find liteweight under Available Apps, and tap Install."
            )
            HStack(spacing: 8) {
                Circle()
                    .fill(isInstalled ? LiteweightTheme.success : LiteweightTheme.warning)
                    .frame(width: 8, height: 8)
                Text(isInstalled ? "Ready · paired and installed" : "Paired · not installed yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiteweightTheme.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(LiteweightTheme.surface, in: Capsule())
            .accessibilityElement(children: .combine)
        } actions: {
            WelcomePrimaryButton(title: "Start Training", action: onFinish)
        }
    }
}
