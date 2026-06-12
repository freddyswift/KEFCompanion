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

    private enum Layout {
        static let labelWidth: CGFloat = 82
        static let segmentedWidth: CGFloat = 178
        static let stepInputWidth: CGFloat = 48
    }

    @State private var ipField: String = ""
    @State private var testResult: TestResult?
    @State private var initialFocusResetToken = 0
    @State private var isManualHostEditorVisible = false
    @State private var volumeStepField = ""
    @State private var lastDiscoveryStartedAt: Date?
    @AppStorage("settingsAdvancedOptionsExpanded") private var isAdvancedOptionsExpanded = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case manualHost
        case volumeStep
    }

    enum TestResult {
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader
            speakersSection
            volumeSettingsSection
            keyboardSettingsSection
            updateSection
        }
        .padding(16)
        .frame(width: MenuPanelLayout.width, alignment: .topLeading)
        .panelWindowBackground()
        .menuPanelSurface()
        .background(SettingsFocusSink(trigger: initialFocusResetToken))
        .onAppear {
            ipField = appState.manualIP
            volumeStepField = "\(appState.volumeStepSize)"
            let hasManualHost = !appState.manualIP.isEmpty
            isManualHostEditorVisible = hasManualHost
            if appState.discovery.isSearching && lastDiscoveryStartedAt == nil {
                lastDiscoveryStartedAt = Date()
            }
            appState.refreshMediaKeyAccessStatus()
            refreshDiscoveryIfNeeded()
            initialFocusResetToken += 1
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .volumeStep && newValue != .volumeStep {
                commitVolumeStepField()
            }
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
        .panelFloatingGlassBackground(Capsule(style: .continuous), fillOpacity: 0.12, strokeOpacity: 0.16)
    }

    private var autoDiscoveryToggle: some View {
        settingsControlRow("Discovery") {
            HStack(spacing: 8) {
                Button {
                    startDiscoveryFromSettings()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                }
                .controlSize(.small)
                .panelFloatingButtonStyle()
                .help("Rescan")
                .disabled(appState.discovery.isSearching || !appState.useAutoDiscovery)

                Toggle("Find speakers automatically", isOn: $appState.useAutoDiscovery)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: appState.useAutoDiscovery) { _, _ in
                        testResult = nil
                        if appState.useAutoDiscovery {
                            lastDiscoveryStartedAt = Date()
                        }
                        appState.startConnection()
                    }
            }
        }
    }

    @ViewBuilder
    private var manualIPEditor: some View {
        if isManualHostEditorVisible {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Connect manually")
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Button(action: manualIPAction) {
                        Label(manualIPActionTitle, systemImage: manualIPActionIcon)
                    }
                    .controlSize(.small)
                    .disabled(ipField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                TextField("192.168.1.40 or speaker.local", text: $ipField)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .manualHost)
                    .onSubmit { applyIP() }
            }
        } else {
            Button {
                isManualHostEditorVisible = true
                DispatchQueue.main.async {
                    focusedField = .manualHost
                }
            } label: {
                Label("Add Manual Host", systemImage: "plus")
            }
            .controlSize(.small)
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
            focusedField = nil
            isManualHostEditorVisible = false
        } else {
            applyIP()
        }
    }

    @ViewBuilder
    private var manualHostStatusRow: some View {
        if let result = testResult {
            switch result {
            case .testing:
                StatusRow(title: "Testing manual host", detail: manualHostStatusDetail, systemImage: "hourglass", tint: .secondary) {
                    ProgressView()
                        .controlSize(.small)
                }
            case .success(let name):
                StatusRow(title: "Manual host connected", detail: name, systemImage: "checkmark.circle.fill", tint: .green)
            case .failure(let message):
                StatusRow(title: "Manual host failed", detail: message, systemImage: "xmark.circle.fill", tint: .red)
            }
        } else if manualHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            StatusRow(title: "Manual host not set", detail: "Use this if discovery misses your speaker.", systemImage: "minus.circle", tint: .secondary)
        } else if manualHostInput != savedManualHost {
            StatusRow(title: "Manual host not saved", detail: "Press Connect to test and save it.", systemImage: "pencil.circle", tint: .orange)
        } else if isSavedManualHostConnected {
            StatusRow(title: "Manual host connected", detail: savedManualHost, systemImage: "checkmark.circle.fill", tint: .green)
        } else {
            StatusRow(title: "Manual host saved", detail: "Will connect to \(savedManualHost) on launch.", systemImage: "link.circle", tint: .secondary)
        }
    }

    private var speakersSection: some View {
        SettingsSection(title: "Speakers", systemImage: "hifispeaker") {
            speakerDiscoveryHeader

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

            connectionOptionsDisclosure
        }
    }

    private var speakerDiscoveryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                VStack(alignment: .leading, spacing: 2) {
                    Text(discoverySummaryText)
                        .font(.subheadline.weight(.medium))

                    Text(discoveryRecencyText(now: timeline.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 10)

            Button {
                startDiscoveryFromSettings()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .panelFloatingButtonStyle()
            .disabled(appState.discovery.isSearching)
        }
        .frame(minHeight: 34)
    }

    private var connectionOptionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.14))
                .frame(height: 1)
                .padding(.top, 2)

            Button {
                var transaction = Transaction()
                transaction.disablesAnimations = true

                withTransaction(transaction) {
                    isAdvancedOptionsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isAdvancedOptionsExpanded ? 90 : 0))
                        .frame(width: 10)

                    Text("Connection Options")
                        .font(.caption.weight(.semibold))

                    Spacer(minLength: 8)

                    Text(connectionOptionsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAdvancedOptionsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    autoDiscoveryToggle
                    manualIPEditor
                    manualHostStatusRow
                }
                .padding(.top, 2)
            }
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func discoveredSpeakerRow(_ speaker: DiscoveredSpeaker) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(discoveredSpeakerDetail(speaker))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if appState.currentHost == speaker.host && appState.isConnected {
                Menu {
                    Button {
                        disconnectSpeaker(speaker)
                    } label: {
                        Label("Disconnect", systemImage: "power")
                    }

                    Button(role: .destructive) {
                        forgetSpeaker(speaker)
                    } label: {
                        Label("Forget Speaker", systemImage: "trash")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label("Current", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Current speaker actions")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .controlSize(.small)
                .help("Current speaker actions")
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
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func discoveredSpeakerDetail(_ speaker: DiscoveredSpeaker) -> String {
        if appState.currentHost == speaker.host && appState.isConnected {
            return "\(speaker.host) · current speaker"
        }

        return speaker.host
    }

    private var volumeSettingsSection: some View {
        SettingsSection(title: "Volume Steps", systemImage: "speaker.wave.2") {
            settingsControlRow("Mode") {
                Picker("Volume control", selection: fixedVolumeStepsBinding) {
                    Text("Any Value").tag(false)
                    Text("Fixed Steps").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: Layout.segmentedWidth)
            }

            if appState.useFixedVolumeSteps {
                volumeStepSizeRow
            }
        }
    }

    private func disconnectSpeaker(_ speaker: DiscoveredSpeaker) {
        guard appState.currentHost == speaker.host else { return }
        appState.disconnect()
        testResult = nil
    }

    private func forgetSpeaker(_ speaker: DiscoveredSpeaker) {
        appState.forgetSpeaker(host: speaker.host)
        if manualHostInput == speaker.host || savedManualHost.isEmpty {
            ipField = appState.manualIP
            testResult = nil
            focusedField = nil
            isManualHostEditorVisible = !appState.manualIP.isEmpty
        }
    }

    private var volumeStepSizeRow: some View {
        settingsControlRow("Step size") {
            volumeStepSizeControl
        }
    }

    private var volumeStepSizeControl: some View {
        HStack(spacing: 6) {
            TextField("5", text: $volumeStepField)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: Layout.stepInputWidth)
                .focused($focusedField, equals: .volumeStep)
                .onSubmit { commitVolumeStepField() }
                .onChange(of: volumeStepField) { _, newValue in
                    updateVolumeStepField(newValue)
                }
                .onChange(of: appState.volumeStepSize) { _, newValue in
                    volumeStepField = "\(newValue)"
                }

            Stepper("Step size", value: volumeStepSizeBinding, in: appState.allowedVolumeStepRange)
                .labelsHidden()
                .help("Change step size")
        }
    }

    private func updateVolumeStepField(_ newValue: String) {
        let digitsOnly = newValue.filter { $0.isNumber }

        guard digitsOnly == newValue else {
            volumeStepField = digitsOnly
            return
        }

        guard let step = Int(digitsOnly) else { return }
        appState.setVolumeStepSize(step)
    }

    private func commitVolumeStepField() {
        guard let step = Int(volumeStepField) else {
            volumeStepField = "\(appState.volumeStepSize)"
            return
        }

        appState.setVolumeStepSize(step)
        volumeStepField = "\(appState.volumeStepSize)"
        focusedField = nil
    }

    private func settingsControlRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Layout.labelWidth, alignment: .leading)

            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 34)
    }

    private var keyboardSettingsSection: some View {
        SettingsSection(title: "Keyboard Volume", systemImage: "keyboard") {
            settingsControlRow("Target") {
                Picker("Keyboard volume target", selection: $appState.volumeKeyRoutingMode) {
                    Text("Mac").tag(VolumeKeyRoutingMode.mac)
                    Text("Auto").tag(VolumeKeyRoutingMode.auto)
                    Text("KEF").tag(VolumeKeyRoutingMode.speaker)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: Layout.segmentedWidth)
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
        settingsControlRow("Defaults") {
            Button {
                resetControlPreferences()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .disabled(appState.usesDefaultControlPreferences)
            .help("Reset volume step and keyboard volume settings")
        }
    }

    private var updateSection: some View {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var connectionOptionsSummary: String {
        if !savedManualHost.isEmpty {
            return "Manual host set"
        }

        return appState.useAutoDiscovery ? "Auto-discovery on" : "Auto-discovery off"
    }

    private func discoveryRecencyText(now: Date) -> String {
        if appState.discovery.isSearching {
            return "Scanning now"
        }

        guard let lastDiscoveryStartedAt else {
            return appState.discovery.speakers.isEmpty ? "Not scanned yet" : "Results from this session"
        }

        let elapsed = now.timeIntervalSince(lastDiscoveryStartedAt)
        if elapsed < 45 {
            return "Last scanned just now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last scanned \(formatter.localizedString(for: lastDiscoveryStartedAt, relativeTo: now))"
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

        startDiscoveryFromSettings()
    }

    private func startDiscoveryFromSettings() {
        lastDiscoveryStartedAt = Date()
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
            set: {
                appState.setVolumeStepSize($0)
                volumeStepField = "\(appState.volumeStepSize)"
            }
        )
    }

    private func resetControlPreferences() {
        appState.resetControlPreferences()
        volumeStepField = "\(appState.volumeStepSize)"
        focusedField = nil
    }

    private var manualHostInput: String {
        ipField.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedManualHost: String {
        appState.manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSavedManualHostConnected: Bool {
        !savedManualHost.isEmpty && appState.isConnected && appState.currentHost == savedManualHost
    }

    private var manualHostStatusDetail: String? {
        manualHostInput.isEmpty ? nil : manualHostInput
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

private struct SettingsFocusSink: NSViewRepresentable {
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
        private var mouseDownMonitor: Any?

        override var acceptsFirstResponder: Bool {
            true
        }

        deinit {
            if let mouseDownMonitor {
                NSEvent.removeMonitor(mouseDownMonitor)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMouseDownMonitorIfNeeded()
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

        private func installMouseDownMonitorIfNeeded() {
            guard mouseDownMonitor == nil else { return }

            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.dismissTextFocusIfNeeded(for: event)
                return event
            }
        }

        private func dismissTextFocusIfNeeded(for event: NSEvent) {
            guard let window, event.window === window, isFirstResponderTextInput(in: window) else {
                return
            }

            guard let contentView = window.contentView else { return }
            let location = contentView.convert(event.locationInWindow, from: nil)
            let hitView = contentView.hitTest(location)
            guard !isTextInputTarget(hitView) else { return }

            window.makeFirstResponder(self)
        }

        private func isFirstResponderTextInput(in window: NSWindow) -> Bool {
            if window.firstResponder is NSTextView {
                return true
            }

            guard let firstResponderView = window.firstResponder as? NSView else {
                return false
            }

            return isTextInputTarget(firstResponderView)
        }

        private func isTextInputTarget(_ view: NSView?) -> Bool {
            var candidate = view
            while let current = candidate {
                if current is NSTextField || current is NSTextView {
                    return true
                }
                candidate = current.superview
            }

            return false
        }
    }
}
