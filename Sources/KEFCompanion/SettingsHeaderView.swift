import SwiftUI

struct SettingsHeaderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.headline.weight(.semibold))
                Text(connectionSummaryDetail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PanelColors.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            connectionStatusBadge
        }
    }

    private var connectionStatusBadge: some View {
        HStack(spacing: 6) {
            if appState.isReconnecting {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(connectionSummaryTint)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }

            Text(connectionSummaryTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(PanelColors.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .panelFloatingGlassBackground(Capsule(style: .continuous), fillOpacity: 0.12, strokeOpacity: 0.16)
    }

    private var connectionSummaryTitle: String {
        if appState.isConnected {
            return "Connected"
        }
        if appState.isReconnecting {
            return "Reconnecting"
        }
        if appState.discovery.isSearching {
            return "Searching"
        }
        return "Not connected"
    }

    private var connectionSummaryDetail: String {
        if appState.isConnected, let host = appState.currentHost {
            let name = appState.speakerName.isEmpty ? "KEF speaker" : appState.speakerName
            return "\(name) at \(host)"
        }

        if appState.isReconnecting, let host = appState.currentHost {
            return "Trying \(host) again."
        }

        if let error = appState.connectionError, !error.isEmpty {
            return error
        }

        if appState.discovery.isSearching {
            return "Scanning the local network."
        }

        return "Use discovery or enter the speaker IP."
    }

    private var connectionSummaryTint: Color {
        if appState.isConnected {
            return .green
        }
        if appState.isReconnecting || appState.discovery.isSearching {
            return .orange
        }
        if appState.connectionError != nil {
            return .red
        }
        return .secondary
    }
}
