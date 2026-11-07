//
//  ActivitySheet.swift
//  liteweight
//
//  Presents the system share controller through SwiftUI's sheet coordinator.
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

    private var isPresented: Binding<Bool> {
        Binding(
            get: { activityItems != nil },
            set: { isPresented in
                if !isPresented {
                    activityItems = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented, onDismiss: { activityItems = nil }) {
                if let activityItems {
                    ActivityViewController(
                        activityItems: activityItems,
                        applicationActivities: applicationActivities,
                        onComplete: { self.activityItems = nil }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async(execute: onComplete)
        }

        // The system uses this anchor only on iPad. A concrete rect prevents
        // UIActivityViewController from raising an exception there.
        controller.popoverPresentationController?.sourceView = controller.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.maxY,
            width: 1,
            height: 1
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
