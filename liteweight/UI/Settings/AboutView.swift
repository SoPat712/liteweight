//
//  AboutView.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 04.03.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(versionString)
                        .font(.liteweightMetric(.body, weight: .semibold))
                } label: {
                    SettingsRowLabel("Version", systemImage: "info.circle.fill", tint: LiteweightTheme.secondaryText)
                }
            } footer: {
                Text("liteweight · Private strength training")
            }

            // One group of links; a "Source Code" heading over a Source Code row read like a mistake.
            Section {
                Link(destination: URL(string: "https://github.com/SoPat712/liteweight")!) {
                    SettingsActionLabel("Source Code", systemImage: "chevron.left.forwardslash.chevron.right",
                                        tint: LiteweightTheme.accent, trailingSymbol: "arrow.up.forward")
                }
                .accessibilityHint("Opens in your browser")
                Link(destination: URL(string: "https://github.com/karimknaebel/Iron")!) {
                    SettingsActionLabel("Built on Iron", systemImage: "hammer.fill",
                                        tint: LiteweightTheme.accent, trailingSymbol: "arrow.up.forward")
                }
                .accessibilityHint("Opens in your browser")
                NavigationLink(destination: LicensesAttributionsView()) {
                    SettingsRowLabel("Licenses & Attributions", systemImage: "doc.text.fill", tint: LiteweightTheme.secondaryText)
                }
            } footer: {
                Text("Original app by Karim Abou Zeid · GPL v3")
            }

            Section("Privacy") {
                Text("Private by design. liteweight has no social feed or public profile. Your workout and body data remain under your control.")
                    .font(.subheadline)
                    .foregroundStyle(LiteweightTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .labeledContentStyle(SettingsValueStyle())
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: LiteweightTheme.floatingWorkoutBottomClearance - 36)
        }
        .navigationTitle("About liteweight")
        .navigationBarTitleDisplayMode(.inline)
        .liteweightScreen()
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        #if DEBUG
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return "\(version ?? "?") (\(build ?? "?"))"
        #else
        return version ?? "?"
        #endif
    }
}

#if DEBUG
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AboutView().mockEnvironment(weightUnit: .metric)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
