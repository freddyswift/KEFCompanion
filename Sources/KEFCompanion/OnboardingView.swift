import SwiftUI

/// First-run panel that resolves the two setup requirements: finding a speaker
/// and choosing keyboard-volume behavior. It exits automatically once the
/// stored app state no longer needs onboarding.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    let doneAction: () -> Void
    let settingsAction: () -> Void

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "KEF Companion"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            speakerStatusCard
            keyboardChoiceCard
            footer
        }
        .padding(16)
        .frame(width: MenuPanelLayout.width, alignment: .topLeading)
        .menuPanelSurface()
        .onAppear {
            appState.refreshMediaKeyAccessStatus()
            if !appState.shouldShowOnboarding {
                appState.completeOnboarding()
                doneAction()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .selectedControlColor).opacity(0.14))
                    .frame(width: 38, height: 38)

                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to KEF Companion")
                    .font(.headline.weight(.semibold))
                Text("Connect a speaker and choose where volume keys go.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var speakerStatusCard: some View {
        OnboardingCard(title: "Speaker", systemImage: "hifispeaker") {
            StatusRow(
                title: speakerStatusTitle,
                detail: speakerStatusDetail,
                systemImage: speakerStatusIcon,
                tint: speakerStatusTint
            ) {
                if appState.discovery.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !appState.isConnected && !appState.discovery.isSearching {
                Button {
                    settingsAction()
                } label: {
                    Label("Choose Speaker", systemImage: "gearshape")
                }
                .controlSize(.small)
            }
        }
    }

    private var keyboardChoiceCard: some View {
        OnboardingCard(title: "Keyboard Volume Keys", systemImage: "keyboard") {
            Picker("Keyboard volume target", selection: $appState.volumeKeyRoutingMode) {
                Text("Mac").tag(VolumeKeyRoutingMode.mac)
                Text("Auto").tag(VolumeKeyRoutingMode.auto)
                Text("KEF").tag(VolumeKeyRoutingMode.speaker)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            keyboardTargetSummary

            if appState.volumeKeyRoutingMode.requiresMediaKeyAccess {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.18))
                    .frame(height: 1)

                inputMonitoringStatus

                if appState.mediaKeyAccessState != .working {
                    permissionActions
                }
            }
        }
    }

    private var inputMonitoringStatus: some View {
        StatusRow(
            title: inputMonitoringTitle,
            detail: inputMonitoringDetail,
            systemImage: mediaKeyStepIcon,
            tint: mediaKeyStepColor
        )
    }

    private var permissionActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    requestPermissionButton
                    openInputMonitoringButton
                    secondaryMediaKeySettingsButton
                    refreshPermissionButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        requestPermissionButton
                        refreshPermissionButton
                    }
                    HStack(spacing: 8) {
                        openInputMonitoringButton
                        secondaryMediaKeySettingsButton
                    }
                }
            }

            if appState.needsRestartForMediaKeyAccess {
                Button {
                    appState.restartApp()
                } label: {
                    Label("Restart KEF Companion", systemImage: "restart.circle")
                }
                .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings") {
                settingsAction()
            }
            .controlSize(.small)

            Spacer()

            Button(primaryActionTitle) {
                doneAction()
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
    }

    private var requestPermissionButton: some View {
        Button {
            appState.requestMediaKeyAccess()
        } label: {
            Label(mediaKeyRequestTitle, systemImage: "hand.raised")
        }
        .controlSize(.small)
    }

    private var openInputMonitoringButton: some View {
        Button {
            appState.openRequiredMediaKeySettings()
        } label: {
            Label(mediaKeySettingsTitle, systemImage: mediaKeySettingsIcon)
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var secondaryMediaKeySettingsButton: some View {
        if appState.mediaKeyAccessState == .failedToActivate {
            Button {
                appState.openAccessibilitySettings()
            } label: {
                Label("Accessibility", systemImage: "accessibility")
            }
            .controlSize(.small)
        }
    }

    private var refreshPermissionButton: some View {
        Button {
            appState.refreshMediaKeyAccessStatus()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
    }

    private var keyboardTargetSummary: some View {
        StatusRow(
            title: keyboardTargetTitle,
            detail: keyboardTargetDetail,
            systemImage: keyboardTargetIcon,
            tint: keyboardTargetTint
        )
    }

    private var speakerStatusTitle: String {
        if appState.isConnected {
            return appState.speakerName.isEmpty ? "Connected" : appState.speakerName
        }

        if appState.discovery.isSearching {
            return "Searching"
        }

        return "No speaker connected"
    }

    private var speakerStatusDetail: String? {
        if appState.isConnected, let host = appState.currentHost {
            return host
        }

        if appState.discovery.isSearching {
            return "Looking on your local network."
        }

        return "Choose a discovered speaker or enter a manual host."
    }

    private var speakerStatusIcon: String {
        if appState.isConnected {
            return "checkmark.circle.fill"
        }

        if appState.discovery.isSearching {
            return "dot.radiowaves.left.and.right"
        }

        return "wifi.exclamationmark"
    }

    private var speakerStatusTint: Color {
        if appState.isConnected {
            return .green
        }

        return appState.discovery.isSearching ? .secondary : .orange
    }

    private var keyboardTargetTitle: String {
        switch appState.volumeKeyRoutingMode {
        case .mac:
            "Controls Mac volume"
        case .auto:
            "Auto-switches volume keys"
        case .speaker:
            "Controls KEF speaker"
        }
    }

    private var keyboardTargetDetail: String? {
        switch appState.volumeKeyRoutingMode {
        case .mac:
            "Keyboard volume keys stay with macOS."
        case .auto:
            "Keys adjust KEF while music plays and macOS when paused."
        case .speaker:
            "Keyboard volume keys adjust the connected speaker."
        }
    }

    private var keyboardTargetIcon: String {
        switch appState.volumeKeyRoutingMode {
        case .mac:
            "macwindow"
        case .auto:
            "arrow.left.arrow.right.circle.fill"
        case .speaker:
            "hifispeaker.fill"
        }
    }

    private var keyboardTargetTint: Color {
        switch appState.volumeKeyRoutingMode {
        case .mac:
            .secondary
        case .auto:
            .blue
        case .speaker:
            .green
        }
    }

    private var primaryActionTitle: String {
        if appState.isConnected {
            return "Done"
        }

        return "Skip for Now"
    }

    private var inputMonitoringTitle: String {
        switch appState.mediaKeyAccessState {
        case .working:
            return appState.volumeKeyRoutingMode == .auto ? "Volume keys ready" : "KEF volume keys ready"
        case .unknown:
            return "Checking permissions"
        case .inputMonitoringNeeded:
            return "Allow Input Monitoring"
        case .inputMonitoringDenied:
            return "Input Monitoring is off"
        case .accessibilityNeeded:
            return "Allow Accessibility"
        case .accessibilityDenied:
            return "Accessibility is off"
        case .failedToActivate:
            return "Volume-key listener failed"
        }
    }

    private var inputMonitoringDetail: String? {
        switch appState.mediaKeyAccessState {
        case .working:
            return appState.volumeKeyRoutingMode == .auto
                ? "When your speaker is playing, volume keys control KEF. When paused, they control your Mac."
                : "Volume keys control your KEF speaker."
        case .unknown:
            return nil
        case .inputMonitoringNeeded:
            return "macOS grants broad key-listening access; \(appDisplayName) uses it only for volume media keys."
        case .inputMonitoringDenied:
            return "Enable \(appDisplayName) in Input Monitoring, then restart."
        case .accessibilityNeeded:
            return "\(appDisplayName) uses Accessibility only to intercept volume keys before macOS changes Mac volume."
        case .accessibilityDenied:
            return "Enable \(appDisplayName) in Accessibility, then restart."
        case .failedToActivate:
            return "Restart \(appDisplayName) or re-add both permissions."
        }
    }

    private var mediaKeyStepIcon: String {
        switch appState.mediaKeyAccessState {
        case .working:
            "checkmark.circle.fill"
        case .accessibilityNeeded, .accessibilityDenied:
            "accessibility"
        default:
            "hand.raised.circle"
        }
    }

    private var mediaKeyStepColor: Color {
        appState.mediaKeyAccessState == .working ? .green : .orange
    }

    private var mediaKeyRequestTitle: String {
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
}

private struct OnboardingCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PanelColors.background.opacity(0.92))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.16), lineWidth: 1)
        }
    }
}
