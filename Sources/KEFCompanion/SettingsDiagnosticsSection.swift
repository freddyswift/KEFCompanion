import AppKit
import SwiftUI

struct SettingsDiagnosticsSection: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateController: UpdateController

    @State private var didCopy = false

    var body: some View {
        SettingsSection(title: "Diagnostics", systemImage: "doc.text.magnifyingglass") {
            StatusRow(
                title: didCopy ? "Diagnostics copied" : "Privacy-safe report",
                detail: "Includes status flags and counts only.",
                systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.doc",
                tint: didCopy ? .green : .secondary
            ) {
                Button {
                    copyDiagnostics()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
                .panelFloatingButtonStyle()
                .help("Copy diagnostics")
            }
        }
    }

    private func copyDiagnostics() {
        let report = PrivacySafeDiagnosticsReport.make(
            appState: appState,
            updateController: updateController
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        didCopy = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
