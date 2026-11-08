import SwiftUI
import UIKit

/// A short, self-dismissing result that drops from the top center as a glass capsule.
/// Use it for outcomes that need no decision (a backup made, a sync done, a status
/// checked). Errors the person has to read or act on keep their sheets and alerts.
struct LiteweightToast: Identifiable, Equatable {
    enum Style { case success, warning, failure, info }

    let id = UUID()
    let title: String
    var subtitle: String?
    var systemImage: String
    var style: Style = .success
    var duration: TimeInterval = 2.4
    /// A single action, such as Undo. Only an action toast takes touches, and only on itself.
    var actionTitle: String?
    var action: (() -> Void)?
    /// Runs when the toast leaves without its action: timed out or replaced by another toast.
    var onExpire: (() -> Void)?

    static func == (lhs: LiteweightToast, rhs: LiteweightToast) -> Bool { lhs.id == rhs.id }

    fileprivate var tint: Color {
        switch style {
        case .success: return LiteweightTheme.success
        case .warning: return LiteweightTheme.warning
        case .failure: return LiteweightTheme.danger
        case .info: return LiteweightTheme.accent
        }
    }
}

/// Shows one toast at a time in its own pass-through window, so it appears above
/// sheets and full-screen covers and never blocks a touch.
@MainActor
final class LiteweightToastCenter: ObservableObject {
    static let shared = LiteweightToastCenter()

    @Published fileprivate private(set) var current: LiteweightToast?
    private var window: LiteweightToastWindow?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ toast: LiteweightToast) {
        installWindowIfNeeded()
        if let previous = current, previous != toast { previous.onExpire?() }
        window?.interactiveFrame = .null
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        withAnimation(LiteweightMotion.preferred(LiteweightMotion.snappy, reduceMotion: reduceMotion)) {
            current = toast
        }
        if SettingsStore.shared.workoutHaptics {
            let generator = UINotificationFeedbackGenerator()
            switch toast.style {
            case .success, .info: generator.notificationOccurred(.success)
            case .warning: generator.notificationOccurred(.warning)
            case .failure: generator.notificationOccurred(.error)
            }
        }
        UIAccessibility.post(notification: .announcement,
                             argument: [toast.title, toast.subtitle].compactMap { $0 }.joined(separator: ", "))
        dismissTask?.cancel()
        // VoiceOver needs time to reach the action after the announcement.
        let duration = toast.action != nil && UIAccessibility.isVoiceOverRunning ? max(toast.duration, 10) : toast.duration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            toast.onExpire?()
            self?.dismiss(toast)
        }
    }

    fileprivate func performAction(_ toast: LiteweightToast) {
        guard current == toast else { return }
        dismissTask?.cancel()
        toast.action?()
        dismiss(toast)
    }

    fileprivate func setInteractiveFrame(_ frame: CGRect) {
        window?.interactiveFrame = frame
    }

    private func dismiss(_ toast: LiteweightToast) {
        guard current == toast else { return }
        window?.interactiveFrame = .null
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        withAnimation(LiteweightMotion.preferred(LiteweightMotion.fade, reduceMotion: reduceMotion)) {
            current = nil
        }
    }

    private func installWindowIfNeeded() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let window = LiteweightToastWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: LiteweightToastOverlay(center: self))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }
}

/// Touches reach the app underneath everywhere except an action toast's own capsule.
private final class LiteweightToastWindow: UIWindow {
    var interactiveFrame: CGRect = .null

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct LiteweightToastOverlay: View {
    @ObservedObject var center: LiteweightToastCenter
    @ObservedObject private var settingsStore = SettingsStore.shared

    var body: some View {
        VStack {
            if let toast = center.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(toast.tint)
                        .symbolEffect(.bounce, value: toast.id)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(toast.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LiteweightTheme.primaryText)
                        if let subtitle = toast.subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(LiteweightTheme.secondaryText)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle = toast.actionTitle, toast.action != nil {
                        Button(actionTitle) { center.performAction(toast) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LiteweightTheme.accent)
                            .frame(minWidth: LiteweightTheme.controlHeight, minHeight: LiteweightTheme.controlHeight)
                            .contentShape(Rectangle())
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                // A frosted layer under the glass keeps text behind it (a nav title, say)
                // from showing through and competing with the message.
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .liteweightLiquidGlassPill(tint: toast.tint.opacity(0.08))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    center.setInteractiveFrame(toast.action == nil ? .null : frame)
                }
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
                .accessibilityElement(children: toast.action == nil ? .ignore : .contain)
                .accessibilityHidden(toast.action == nil) // Plain toasts are announced instead.
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
        .preferredColorScheme(settingsStore.appearance.colorScheme)
    }
}
