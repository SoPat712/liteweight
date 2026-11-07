//
//  ActivitySheet.swift
//  liteweight
//
//  Presents the system share controller the UIKit way, so iOS sizes it.
//  Wrapping it in a SwiftUI sheet with our own detents clipped its bottom row.
//

import SwiftUI

extension View {
    func liteweightActivitySheet(
        activityItems: Binding<[Any]?>,
        applicationActivities: [UIActivity]? = nil
    ) -> some View {
        modifier(
            LiteweightActivitySheetModifier(
                activityItems: activityItems,
                applicationActivities: applicationActivities
            )
        )
    }
}

private struct LiteweightActivitySheetModifier: ViewModifier {
    @Binding var activityItems: [Any]?
    let applicationActivities: [UIActivity]?

    func body(content: Content) -> some View {
        content
            .background(
                ActivityPresenter(
                    activityItems: $activityItems,
                    applicationActivities: applicationActivities
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            )
    }
}

private struct ActivityPresenter: UIViewControllerRepresentable {
    @Binding var activityItems: [Any]?
    let applicationActivities: [UIActivity]?

    final class Coordinator {
        weak var activityController: UIActivityViewController?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isUserInteractionEnabled = false
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        guard let activityItems else {
            if let controller = context.coordinator.activityController,
               controller.presentingViewController != nil,
               !controller.isBeingDismissed {
                controller.dismiss(animated: true)
            }
            return
        }

        guard context.coordinator.activityController == nil else { return }

        var presenter = host
        while let presented = presenter.presentedViewController,
              !presented.isBeingDismissed {
            presenter = presented
        }

        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        let activityItemsBinding = $activityItems
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                activityItemsBinding.wrappedValue = nil
            }
        }

        // The system uses this anchor only on iPad. A concrete rect prevents
        // UIActivityViewController from raising an exception there.
        controller.popoverPresentationController?.sourceView = host.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: host.view.bounds.midX,
            y: host.view.bounds.midY,
            width: 1,
            height: 1
        )
        context.coordinator.activityController = controller
        presenter.present(controller, animated: true)
    }
}
