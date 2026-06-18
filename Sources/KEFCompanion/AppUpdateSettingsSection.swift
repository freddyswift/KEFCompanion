import SwiftUI

struct AppUpdateSettingsSection: View {
    @EnvironmentObject private var updateController: UpdateController

    var body: some View {
        SettingsSection(title: "App Updates", systemImage: "arrow.down.circle") {
            updateStatusRow
        }
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(updateStatusTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(updateStatusDetail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PanelColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if updateController.configurationState == .ready {
                updateCheckButton
            }
        }
        .frame(minHeight: 34)
    }

    private var updateCheckButton: some View {
        Button {
            updateController.checkForUpdates()
        } label: {
            Label("Check Now", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
        .panelFloatingButtonStyle()
        .disabled(!updateController.canCheckForUpdates)
        .help("Check for updates")
    }

    private var appVersionSummary: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(shortVersion) (\(build))"
    }

    private var updateStatusTitle: String {
        switch updateController.configurationState {
        case .ready:
            "Automatic updates"
        case .localBuild:
            "Source build"
        }
    }

    private var updateStatusDetail: String {
        switch updateController.configurationState {
        case .ready:
            return appVersionSummary
        case .localBuild:
            return "Updates unavailable in source builds."
        }
    }
}
