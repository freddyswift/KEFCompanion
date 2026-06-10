import AppKit
import SwiftUI

/// Settings window for connection management, volume behavior, media-key
/// permissions, and update status.
///
/// Most rows bind directly to `AppState`. Temporary UI-only state, such as the
/// manual host text field and the last connection-test result, stays local to
/// this view so partially typed settings are not persisted until validation
/// succeeds.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updateController: UpdateController

    @State private var ipField: String = ""
    @State private var testResult: TestResult?
    @State private var initialFocusResetToken = 0

    enum TestResult {
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader
            connectionSection
            discoveredSpeakersSection
            volumeSettingsSection
            keyboardSettingsSection
            updateSection
        }
        .padding(16)
        .frame(width: MenuPanelLayout.width, alignment: .topLeading)
        .background(PanelColors.settingsBackground)
        .menuPanelSurface()
        .background(InitialFocusSink(trigger: initialFocusResetToken))
        .onAppear {
            ipField = appState.manualIP
            appState.refreshMediaKeyAccessStatus()
            refreshDiscoveryIfNeeded()
            initialFocusResetToken += 1
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.headline.weight(.semibold))
                Text(connectionSummaryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(PanelColors.controlFill)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(PanelColors.sectionStroke, lineWidth: 1)
        }
    }

    private var connectionSection: some View {
        SettingsSection(title: "Connection", systemImage: "dot.radiowaves.left.and.right") {
            autoDiscoveryToggle
            settingsDivider
            manualIPEditor
            testResultView
        }
    }

    private var autoDiscoveryToggle: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-discovery")
                    .font(.subheadline)
                Text("Find speakers on the local network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                appState.discovery.startDiscovery()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
            }
            .controlSize(.small)
            .help("Rescan")
            .disabled(appState.discovery.isSearching || !appState.useAutoDiscovery)

            Toggle("Auto-discovery", isOn: $appState.useAutoDiscovery)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: appState.useAutoDiscovery) { _, _ in
                    testResult = nil
                    appState.startConnection()
                }
        }
    }

    private var manualIPEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label("Manual Host", systemImage: "network")
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 8)

                Button(action: manualIPAction) {
                    Label(manualIPActionTitle, systemImage: manualIPActionIcon)
                }
                .controlSize(.small)
                .disabled(ipField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("192.168.1.40 or speaker.local", text: $ipField)
                .textFieldStyle(.roundedBorder)
                .onSubmit { applyIP() }
        }
    }

    private var manualIPActionTitle: String {
        isManualIPCurrentConnection ? "Disconnect" : "Connect"
    }

    private var manualIPActionIcon: String {
        isManualIPCurrentConnection ? "xmark.circle" : "link"
    }

    private var isManualIPCurrentConnection: Bool {
        guard appState.isConnected, let currentHost = appState.currentHost else {
            return false
        }

        return ipField.trimmingCharacters(in: .whitespacesAndNewlines) == currentHost
    }

    private func manualIPAction() {
        if isManualIPCurrentConnection {
            appState.disconnect()
            appState.manualIP = ""
            ipField = ""
            testResult = nil
        } else {
            applyIP()
        }
    }

    @ViewBuilder
    private var testResultView: some View {
        if let result = testResult {
            switch result {
            case .testing:
                StatusRow(title: "Testing connection", detail: nil, systemImage: "hourglass", tint: .secondary) {
                    ProgressView()
                        .controlSize(.small)
                }
            case .success(let name):
                StatusRow(title: "Connected to \(name)", detail: nil, systemImage: "checkmark.circle.fill", tint: .green)
            case .failure(let message):
                StatusRow(title: message, detail: nil, systemImage: "xmark.circle.fill", tint: .red)
            }
        }
    }

    private var discoveredSpeakersSection: some View {
        SettingsSection(title: "Discovered Speakers", systemImage: "hifispeaker") {
            HStack(alignment: .center, spacing: 8) {
                Text(discoverySummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    appState.discovery.startDiscovery()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(appState.discovery.isSearching)
            }

            if appState.discovery.isSearching {
                StatusRow(title: "Scanning your network", detail: nil, systemImage: "dot.radiowaves.left.and.right", tint: .secondary) {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if displayedDiscoveredSpeakers.isEmpty && !appState.discovery.isSearching {
                StatusRow(
                    title: "No speakers found",
                    detail: "Rescan or enter a manual host.",
                    systemImage: "wifi.exclamationmark",
                    tint: .secondary
                )
            }

            ForEach(displayedDiscoveredSpeakers) { speaker in
                discoveredSpeakerRow(speaker)
            }
        }
    }

    private func discoveredSpeakerRow(_ speaker: DiscoveredSpeaker) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(speaker.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if appState.currentHost == speaker.host && appState.isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Current speaker")
            } else {
                Button {
                    ipField = speaker.host
                    applyIP()
                } label: {
                    Label("Use", systemImage: "checkmark")
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PanelColors.rowFill)
        )
    }

    private var volumeSettingsSection: some View {
        SettingsSection(title: "Volume Control", systemImage: "speaker.wave.2") {
            Picker("Volume control", selection: fixedVolumeStepsBinding) {
                Text("Any Value").tag(false)
                Text("Fixed Steps").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            if appState.useFixedVolumeSteps {
                settingsDivider
                volumeStepSizeRow
            }
        }
    }

    private var volumeStepSizeRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Label("Step size", systemImage: "number")
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 8)

            Stepper(value: volumeStepSizeBinding, in: appState.allowedVolumeStepRange) {
                Text("\(appState.volumeStepSize)")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 24, alignment: .trailing)
            }
        }
    }

    private var keyboardSettingsSection: some View {
        SettingsSection(title: "Keyboard Volume Keys", systemImage: "keyboard") {
            Picker("Keyboard volume target", selection: $appState.volumeKeyRoutingMode) {
                Text("Mac").tag(VolumeKeyRoutingMode.mac)
                Text("Auto").tag(VolumeKeyRoutingMode.auto)
                Text("KEF").tag(VolumeKeyRoutingMode.speaker)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            if appState.volumeKeyRoutingMode.requiresMediaKeyAccess {
                settingsDivider
                mediaKeyStatusRow
            }

            if shouldShowMediaKeyHelp {
                mediaKeyHelp
            }
        }
    }

    private var updateSection: some View {
        SettingsSection(title: "Updates", systemImage: "arrow.down.circle") {
            StatusRow(
                title: updateStatusTitle,
                detail: updateStatusDetail,
                systemImage: updateStatusIcon,
                tint: updateStatusColor
            ) {
                Button {
                    updateController.checkForUpdates()
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(!updateController.canCheckForUpdates)
                .help("Check for updates")
            }
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

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.18))
            .frame(height: 1)
    }

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "KEF Companion"
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
            return "\(appVersionSummary). Release update feed unavailable."
        }
    }

    private var updateStatusIcon: String {
        switch updateController.configurationState {
        case .ready:
            "arrow.down.circle.fill"
        case .localBuild:
            "hammer"
        }
    }

    private var updateStatusColor: Color {
        switch updateController.configurationState {
        case .ready:
            .green
        case .localBuild:
            .secondary
        }
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

    private var discoverySummaryText: String {
        if appState.discovery.isSearching {
            return "Scanning"
        }

        let count = displayedDiscoveredSpeakers.count
        if count == 1 {
            return "1 speaker found"
        }

        return "\(count) speakers found"
    }

    private var displayedDiscoveredSpeakers: [DiscoveredSpeaker] {
        var speakers = appState.discovery.speakers

        guard appState.isConnected,
              let host = appState.currentHost,
              !speakers.contains(where: { $0.host == host }) else {
            return speakers
        }

        let name = appState.speakerName.isEmpty ? "Connected speaker" : appState.speakerName
        speakers.insert(
            DiscoveredSpeaker(id: "current-\(host)", name: name, host: host, macAddress: nil),
            at: 0
        )
        return speakers
    }

    private func refreshDiscoveryIfNeeded() {
        // Opening Settings is a strong signal that the user is trying to choose
        // a speaker, so start a scan if auto-discovery is enabled and no
        // current results are available.
        guard appState.useAutoDiscovery,
              appState.discovery.speakers.isEmpty,
              !appState.discovery.isSearching else {
            return
        }

        appState.discovery.startDiscovery()
    }

    private var fixedVolumeStepsBinding: Binding<Bool> {
        Binding(
            get: { appState.useFixedVolumeSteps },
            set: { appState.setUseFixedVolumeSteps($0) }
        )
    }

    private var volumeStepSizeBinding: Binding<Int> {
        Binding(
            get: { appState.volumeStepSize },
            set: { appState.setVolumeStepSize($0) }
        )
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
                return "When your speaker is playing, volume keys control KEF. When paused, they control your Mac."
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

    private func applyIP() {
        let host = ipField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }

        // Validate before persisting. This prevents malformed hosts from
        // becoming the startup connection target in `AppState.startConnection`.
        guard let normalizedHost = ManualHostValidator.normalizedHost(host) else {
            testResult = .failure("Enter a private local IP address or .local host.")
            return
        }

        ipField = normalizedHost

        testResult = .testing
        let api = KEFSpeakerAPI(host: normalizedHost)

        Task { @MainActor in
            let ok = await api.testConnection()
            if ok {
                let name = (try? await api.getSpeakerName()) ?? normalizedHost
                testResult = .success(name)
                appState.manualIP = normalizedHost
                appState.connect(to: normalizedHost)
            } else {
                testResult = .failure("Cannot reach speaker at \(normalizedHost)")
            }
        }
    }
}

private struct InitialFocusSink: NSViewRepresentable {
    let trigger: Int

    func makeNSView(context: Context) -> FocusSinkView {
        FocusSinkView()
    }

    func updateNSView(_ nsView: FocusSinkView, context: Context) {
        nsView.activateOnce(for: trigger)
    }

    final class FocusSinkView: NSView {
        private var activatedTrigger: Int?
        private var pendingTrigger: Int?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            activatePendingTrigger()
        }

        func activateOnce(for trigger: Int) {
            guard activatedTrigger != trigger else { return }
            pendingTrigger = trigger
            activatePendingTrigger()
        }

        private func activatePendingTrigger() {
            guard let pendingTrigger, activatedTrigger != pendingTrigger, let window else {
                return
            }

            activatedTrigger = pendingTrigger
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                window.initialFirstResponder = self
                window.makeFirstResponder(self)
            }
        }
    }
}
