import SwiftUI

struct KeyboardVolumeSettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsSection(title: "Keyboard Volume", systemImage: "keyboard") {
            SettingsControlRow("Target") {
                Picker("Keyboard volume target", selection: $appState.volumeKeyRoutingMode) {
                    Text("Mac").tag(VolumeKeyRoutingMode.mac)
                    Text("Auto").tag(VolumeKeyRoutingMode.auto)
                    Text("KEF").tag(VolumeKeyRoutingMode.speaker)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: SettingsMetrics.segmentedWidth)
            }

            if appState.volumeKeyRoutingMode.requiresMediaKeyAccess {
                mediaKeyStatusRow
            }

            if shouldShowMediaKeyHelp {
                mediaKeyHelp
            }

            if !appState.usesDefaultControlPreferences {
                resetControlPreferencesRow
            }
        }
    }

    private var resetControlPreferencesRow: some View {
        SettingsControlRow("Defaults") {
            Button {
                appState.resetControlPreferences()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .disabled(appState.usesDefaultControlPreferences)
            .help("Reset volume step and keyboard volume settings")
        }
    }

    private var mediaKeyStatusRow: some View {
        StatusRow(
            title: mediaKeyStatusTitle,
            detail: mediaKeyStatusDetail,
            systemImage: mediaKeyStatusIcon,
            tint: mediaKeyStatusColor
        )
    }

    private var mediaKeyHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            mediaKeyActionButtons

            if appState.needsRestartForMediaKeyAccess {
                restartNotice
            }
        }
    }

    private var restartNotice: some View {
        StatusRow(title: "Restart required", detail: "Quit and reopen \(appDisplayName).", systemImage: "restart.circle", tint: .orange) {
            Button {
                appState.restartApp()
            } label: {
                Image(systemName: "restart.circle")
                    .frame(width: 16, height: 16)
            }
            .controlSize(.small)
            .help("Restart KEF Companion")
        }
    }

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "KEF Companion"
    }

    private var mediaKeyStatusTitle: String {
        if !appState.volumeKeyRoutingMode.requiresMediaKeyAccess {
            return "Off"
        }

        return switch appState.mediaKeyAccessState {
        case .unknown:
            "Checking permissions"
        case .working:
            appState.volumeKeyRoutingMode == .auto ? "Volume keys ready" : "KEF volume keys ready"
        case .inputMonitoringNeeded:
            "Allow Input Monitoring"
        case .inputMonitoringDenied:
            "Input Monitoring is off"
        case .accessibilityNeeded:
            "Allow Accessibility"
        case .accessibilityDenied:
            "Accessibility is off"
        case .failedToActivate:
            "Volume-key listener failed"
        }
    }

    private var mediaKeyStatusIcon: String {
        if !appState.volumeKeyRoutingMode.requiresMediaKeyAccess {
            return "speaker.slash"
        }

        return switch appState.mediaKeyAccessState {
        case .unknown:
            "questionmark.circle"
        case .working:
            "checkmark.circle.fill"
        case .inputMonitoringNeeded:
            "hand.raised.circle"
        case .inputMonitoringDenied:
            "exclamationmark.triangle.fill"
        case .accessibilityNeeded, .accessibilityDenied:
            "accessibility"
        case .failedToActivate:
            "xmark.circle.fill"
        }
    }

    private var mediaKeyStatusDetail: String? {
        guard appState.volumeKeyRoutingMode.requiresMediaKeyAccess else { return nil }

        switch appState.mediaKeyAccessState {
        case .working:
            switch appState.volumeKeyRoutingMode {
            case .auto:
                return "KEF while playing. Mac when paused."
            case .speaker:
                return "Volume keys control your KEF speaker."
            case .mac:
                return "Volume keys control your Mac."
            }
        case .unknown:
            return nil
        case .inputMonitoringNeeded,
             .inputMonitoringDenied,
             .accessibilityNeeded,
             .accessibilityDenied,
             .failedToActivate:
            return appState.mediaKeyAccessMessage
        }
    }

    private var mediaKeyStatusColor: Color {
        if !appState.volumeKeyRoutingMode.requiresMediaKeyAccess {
            return .secondary
        }

        return switch appState.mediaKeyAccessState {
        case .unknown:
            .secondary
        case .working:
            .green
        case .inputMonitoringNeeded,
             .inputMonitoringDenied,
             .accessibilityNeeded,
             .accessibilityDenied:
            .orange
        case .failedToActivate:
            .red
        }
    }

    private var shouldShowMediaKeyHelp: Bool {
        appState.volumeKeyRoutingMode.requiresMediaKeyAccess && appState.mediaKeyAccessState != .working
    }

    private var mediaKeyActionTitle: String {
        switch appState.mediaKeyAccessState {
        case .inputMonitoringNeeded:
            "Request Permission"
        case .inputMonitoringDenied:
            "Retry Permission"
        case .accessibilityNeeded:
            "Request Permission"
        case .accessibilityDenied:
            "Retry Permission"
        case .failedToActivate:
            "Retry Listener"
        case .unknown, .working:
            "Request Permission"
        }
    }

    private var mediaKeySettingsTitle: String {
        switch appState.mediaKeyAccessState {
        case .accessibilityNeeded, .accessibilityDenied:
            "Open Accessibility"
        default:
            "Open Input Monitoring"
        }
    }

    private var mediaKeySettingsIcon: String {
        switch appState.mediaKeyAccessState {
        case .accessibilityNeeded, .accessibilityDenied:
            "accessibility"
        default:
            "gearshape"
        }
    }

    private var mediaKeyActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                mediaKeyPermissionButton
                mediaKeySettingsButton
                mediaKeyRefreshButton
                secondaryMediaKeySettingsButton
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    mediaKeyPermissionButton
                    mediaKeyRefreshButton
                }
                HStack(spacing: 8) {
                    mediaKeySettingsButton
                    secondaryMediaKeySettingsButton
                }
            }
        }
    }

    @ViewBuilder
    private var mediaKeyPermissionButton: some View {
        if appState.volumeKeyRoutingMode.requiresMediaKeyAccess && appState.mediaKeyAccessState != .working {
            Button {
                appState.requestMediaKeyAccess()
            } label: {
                Label(mediaKeyActionTitle, systemImage: "hand.raised")
            }
            .controlSize(.small)
        }
    }

    private var mediaKeySettingsButton: some View {
        Button {
            appState.openRequiredMediaKeySettings()
        } label: {
            Label(mediaKeySettingsTitle, systemImage: mediaKeySettingsIcon)
        }
        .controlSize(.small)
        .help(mediaKeySettingsTitle)
    }

    @ViewBuilder
    private var secondaryMediaKeySettingsButton: some View {
        if appState.mediaKeyAccessState == .failedToActivate {
            Button {
                appState.openAccessibilitySettings()
            } label: {
                Label("Open Accessibility", systemImage: "accessibility")
            }
            .controlSize(.small)
            .help("Open Accessibility")
        }
    }

    private var mediaKeyRefreshButton: some View {
        Button {
            appState.refreshMediaKeyAccessStatus()
        } label: {
            Label("Check Again", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
        .disabled(!appState.volumeKeyRoutingMode.requiresMediaKeyAccess)
        .help("Check permissions again")
    }
}
