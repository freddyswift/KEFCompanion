import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    /// Media-key permissions are modeled separately from the chosen routing
    /// mode. A user can request KEF routing while macOS still blocks the event
    /// tap, so the UI needs to represent both preference and permission state.
    enum MediaKeyAccessState {
        case unknown
        case working
        case inputMonitoringNeeded
        case inputMonitoringDenied
        case accessibilityNeeded
        case accessibilityDenied
        case failedToActivate
    }

    // Connection
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var currentHost: String?
    @Published private(set) var isReconnecting = false

    // Speaker state
    @Published var speakerName: String = ""
    @Published var speakerModel: String = ""
    @Published var status: SpeakerStatus = .standby
    @Published var source: SpeakerSource = .wifi
    @Published var volume: Int = 0
    @Published private(set) var displayedVolume: Int = 0
    @Published var isPlaying = false
    @Published var nowPlaying: NowPlayingInfo?

    // Busy state — set during actions that take time to reflect
    @Published var isBusy = false

    // Settings (persisted)
    @AppStorage("manualIP") var manualIP: String = ""
    @AppStorage("useAutoDiscovery") var useAutoDiscovery: Bool = true
    @AppStorage("volumeKeyRoutingMode") var volumeKeyRoutingMode: VolumeKeyRoutingMode = .auto {
        didSet {
            refreshMediaKeyAccessStatus()
        }
    }
    @AppStorage("useFixedVolumeSteps") private var storedUseFixedVolumeSteps: Bool = true
    @AppStorage("volumeStepSize") private var storedVolumeStepSize: Int = 5
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("hasRequestedMediaKeyAccess") private var hasRequestedMediaKeyAccess = false
    @AppStorage("hasRequestedAccessibilityAccess") private var hasRequestedAccessibilityAccess = false
    @AppStorage("lastConnectedHost") private var lastConnectedHost: String = ""

    // Discovery
    let discovery = KEFDiscovery()

    // Internal controllers and task state. `AppState` remains the app-facing
    // coordinator, but long-lived loops and pure policies live in smaller types.
    private var speaker: KEFSpeakerClient?
    private var connectionTask: Task<Void, Never>?
    private let pollingController = SpeakerPollingController()
    private var consecutiveRefreshFailures = 0
    private var pendingCommittedVolume: Int?
    private var pendingVolumeResetTask: Task<Void, Never>?
    private var volumeBeforeMediaKeyMute: Int?
    private var mediaKeyRestartWasRequestedThisSession = false
    private let volumeHUD = VolumeHUDController()
    private var isVolumeHUDSuppressed = false
    private lazy var mediaKeyController = MediaKeyController(
        onVolumeDelta: { [weak self] delta in
            self?.handleVolumeKey(delta) ?? false
        },
        onMuteToggle: { [weak self] in
            self?.handleMuteKey() ?? false
        }
    )

    @Published private(set) var mediaKeyAccessState: MediaKeyAccessState = .unknown
    @Published private(set) var mediaKeyAccessMessage = ""
    @Published private(set) var needsRestartForMediaKeyAccess = false

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "KEF Companion"
    }

    init() {
        migrateLegacyVolumeKeyPreference()
        refreshMediaKeyAccessStatus()
        startConnection()
    }

    var allowedVolumeStepRange: ClosedRange<Int> {
        VolumePolicy.allowedStepRange
    }

    var useFixedVolumeSteps: Bool {
        storedUseFixedVolumeSteps
    }

    var volumeStepSize: Int {
        Self.clampedVolumeStep(storedVolumeStepSize)
    }

    var effectiveVolumeStep: Int {
        useFixedVolumeSteps ? volumeStepSize : 1
    }

    var volumeSliderStep: Double {
        Double(effectiveVolumeStep)
    }

    var usesDefaultControlPreferences: Bool {
        useFixedVolumeSteps && volumeStepSize == 5 && volumeKeyRoutingMode == .auto
    }

    func setUseFixedVolumeSteps(_ enabled: Bool) {
        guard storedUseFixedVolumeSteps != enabled else { return }
        objectWillChange.send()
        storedUseFixedVolumeSteps = enabled
    }

    func setVolumeStepSize(_ step: Int) {
        let clampedStep = Self.clampedVolumeStep(step)
        guard storedVolumeStepSize != clampedStep else { return }
        objectWillChange.send()
        storedVolumeStepSize = clampedStep
    }

    func resetControlPreferences() {
        setUseFixedVolumeSteps(true)
        setVolumeStepSize(5)
        volumeKeyRoutingMode = .auto
    }

    private static func clampedVolumeStep(_ step: Int) -> Int {
        VolumePolicy.clampedStepSize(step)
    }

    private var volumePolicy: VolumePolicy {
        VolumePolicy(usesFixedSteps: useFixedVolumeSteps, stepSize: volumeStepSize)
    }

    func setVolumeHUDSuppressed(_ suppressed: Bool) {
        isVolumeHUDSuppressed = suppressed
        if suppressed {
            volumeHUD.hide()
        }
    }

    func refreshMediaKeyAccessStatus() {
        guard volumeKeyRoutingMode.requiresMediaKeyAccess else {
            mediaKeyController.invalidate()
            mediaKeyRestartWasRequestedThisSession = false
            needsRestartForMediaKeyAccess = false
            mediaKeyAccessState = .unknown
            mediaKeyAccessMessage = "Volume keys will control macOS system volume."
            return
        }

        guard MediaKeyController.hasListenAccess else {
            mediaKeyController.invalidate()
            needsRestartForMediaKeyAccess = mediaKeyRestartWasRequestedThisSession
            mediaKeyAccessState = hasRequestedMediaKeyAccess ? .inputMonitoringDenied : .inputMonitoringNeeded
            mediaKeyAccessMessage = hasRequestedMediaKeyAccess
                ? "Enable \(appDisplayName) in Input Monitoring, then restart."
                : "macOS grants broad key-listening access; \(appDisplayName) uses it only for volume media keys."
            return
        }

        guard MediaKeyController.hasAccessibilityAccess else {
            mediaKeyController.invalidate()
            needsRestartForMediaKeyAccess = mediaKeyRestartWasRequestedThisSession
            mediaKeyAccessState = hasRequestedAccessibilityAccess ? .accessibilityDenied : .accessibilityNeeded
            mediaKeyAccessMessage = hasRequestedAccessibilityAccess
                ? "Enable \(appDisplayName) in Accessibility, then restart."
                : "\(appDisplayName) uses Accessibility only to intercept volume keys before macOS changes Mac volume."
            return
        }

        switch mediaKeyController.activate() {
        case .working:
            mediaKeyAccessState = .working
            mediaKeyRestartWasRequestedThisSession = false
            needsRestartForMediaKeyAccess = false
            mediaKeyAccessMessage = "Ready."
        case .missingAccessibility:
            mediaKeyController.invalidate()
            needsRestartForMediaKeyAccess = mediaKeyRestartWasRequestedThisSession
            mediaKeyAccessState = hasRequestedAccessibilityAccess ? .accessibilityDenied : .accessibilityNeeded
            mediaKeyAccessMessage = hasRequestedAccessibilityAccess
                ? "Enable \(appDisplayName) in Accessibility, then restart."
                : "\(appDisplayName) uses Accessibility only to intercept volume keys before macOS changes Mac volume."
        case .failed:
            mediaKeyAccessState = .failedToActivate
            needsRestartForMediaKeyAccess = true
            mediaKeyAccessMessage = "macOS refused the listener. Restart or re-add permissions."
        }
    }

    func requestMediaKeyAccess() {
        guard volumeKeyRoutingMode.requiresMediaKeyAccess else {
            refreshMediaKeyAccessStatus()
            return
        }

        if !MediaKeyController.hasListenAccess {
            hasRequestedMediaKeyAccess = true
            mediaKeyRestartWasRequestedThisSession = true
            MediaKeyController.requestListenAccess()
        } else if !MediaKeyController.hasAccessibilityAccess {
            hasRequestedAccessibilityAccess = true
            mediaKeyRestartWasRequestedThisSession = true
            MediaKeyController.requestAccessibilityAccess()
        } else {
            mediaKeyController.invalidate()
            mediaKeyRestartWasRequestedThisSession = true
        }

        refreshMediaKeyAccessStatus()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    var shouldShowOnboarding: Bool {
        if hasCompletedOnboarding {
            return false
        }

        if !isConnected {
            return true
        }

        return volumeKeyRoutingMode.requiresMediaKeyAccess && mediaKeyAccessState != .working
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openRequiredMediaKeySettings() {
        switch mediaKeyAccessState {
        case .accessibilityNeeded, .accessibilityDenied:
            openAccessibilitySettings()
        default:
            openInputMonitoringSettings()
        }
    }

    func restartApp() {
        let bundleURL = Bundle.main.bundleURL

        if bundleURL.pathExtension == "app" {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "sleep 0.4; /usr/bin/open \(shellQuoted(bundleURL.path))"]
            try? task.run()
        }

        NSApplication.shared.terminate(nil)
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // MARK: - Connection

    func startConnection() {
        disconnect()

        let manualHost = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manualHost.isEmpty {
            connect(to: manualHost)
            return
        }

        guard useAutoDiscovery else { return }

        discovery.startDiscovery()
        connectionTask = Task { @MainActor in
            var attemptedHosts = Set<String>()

            if !lastConnectedHost.isEmpty {
                attemptedHosts.insert(lastConnectedHost)
                if await establishConnection(to: lastConnectedHost, retryCount: 2) {
                    return
                }
            }

            let deadline = ContinuousClock.now + .seconds(14)
            while ContinuousClock.now < deadline {
                guard !Task.isCancelled else { return }

                let candidates = discovery.speakers
                    .map(\.host)
                    .filter { !attemptedHosts.contains($0) }

                for host in candidates {
                    attemptedHosts.insert(host)
                    if await establishConnection(to: host, retryCount: 2) {
                        return
                    }
                }

                try? await Task.sleep(for: .milliseconds(500))
            }

            guard !Task.isCancelled else { return }
            discovery.stopDiscovery()
            if speaker == nil {
                isConnected = false
                isReconnecting = false
                connectionError = "No KEF speaker found"
            }
        }
    }

    func connect(to host: String) {
        disconnect()

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }

        connectionTask = Task { @MainActor in
            let connected = await establishConnection(to: trimmedHost, retryCount: 3)
            guard !Task.isCancelled else { return }

            if !connected {
                isConnected = false
                isReconnecting = false
                connectionError = "Cannot reach speaker at \(trimmedHost)"
                speaker = nil
                currentHost = nil
            }
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        discovery.stopDiscovery()
        pollingController.stop()
        speaker = nil
        isConnected = false
        isReconnecting = false
        currentHost = nil
        connectionError = nil
        consecutiveRefreshFailures = 0
        speakerName = ""
        speakerModel = ""
        status = .standby
        source = .wifi
        volume = 0
        displayedVolume = 0
        volumeBeforeMediaKeyMute = nil
        isPlaying = false
        nowPlaying = nil
        isBusy = false
        clearPendingVolume(keepDisplayedVolume: false)
        volumeHUD.hide()
    }

    func forgetSpeaker(host: String) {
        let forgottenHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !forgottenHost.isEmpty else { return }

        objectWillChange.send()
        if manualIP.trimmingCharacters(in: .whitespacesAndNewlines) == forgottenHost {
            manualIP = ""
        }
        if lastConnectedHost == forgottenHost {
            lastConnectedHost = ""
        }

        if currentHost == forgottenHost {
            disconnect()
        }
    }

    @discardableResult
    private func establishConnection(to host: String, retryCount: Int) async -> Bool {
        let api = KEFSpeakerAPI(host: host)
        speaker = api
        currentHost = host
        isReconnecting = true
        connectionError = nil

        for attempt in 0..<retryCount {
            guard !Task.isCancelled, self.speaker === api else { return false }

            if await api.testConnection() {
                guard !Task.isCancelled, self.speaker === api else { return false }
                markConnectionHealthy(for: api, stopDiscovery: true)
                await refresh()
                startPolling()
                return true
            }

            if attempt < retryCount - 1 {
                try? await Task.sleep(for: connectionRetryDelay(afterAttempt: attempt))
            }
        }

        guard self.speaker === api else { return false }
        speaker = nil
        currentHost = nil
        isConnected = false
        isReconnecting = false
        return false
    }

    private func connectionRetryDelay(afterAttempt attempt: Int) -> Duration {
        switch attempt {
        case 0:
            return .milliseconds(500)
        case 1:
            return .seconds(1)
        default:
            return .seconds(2)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingController.start(
            refresh: { [weak self] in
                await self?.refresh()
            },
            refreshPlaybackStateForVolumeRouting: { [weak self] in
                await self?.refreshPlaybackStateForVolumeRouting()
            }
        )
    }

    /// Auto routing needs fresher playback state than the full 3-second refresh.
    /// This lightweight poll only runs when the current source uses playback
    /// state to decide whether volume keys should control the speaker or macOS.
    private func refreshPlaybackStateForVolumeRouting() async {
        guard volumeKeyRoutingMode == .auto,
              source.usesPlaybackStateForVolumeRouting,
              status == .powerOn,
              let speaker else {
            return
        }

        do {
            let refreshedIsPlaying = try await speaker.getIsPlaying()
            guard self.speaker === speaker else { return }
            updateIfChanged(\.isPlaying, refreshedIsPlaying)
            if !refreshedIsPlaying {
                updateIfChanged(\.nowPlaying, nil)
            }
        } catch {
            guard self.speaker === speaker else { return }
        }
    }

    func refresh() async {
        guard let speaker else { return }

        do {
            async let s = speaker.getStatus()
            async let src = speaker.getSource()
            async let vol = speaker.getVolume()
            async let name = speaker.getSpeakerName()
            async let model = speaker.getModel()

            let refreshedVolume = try await vol
            let refreshedStatus = try await s
            let refreshedSource = try await src
            let refreshedName = try await name
            let refreshedModel = try await model

            guard self.speaker === speaker else { return }

            updateIfChanged(\.status, refreshedStatus)
            updateIfChanged(\.source, refreshedSource)
            updateIfChanged(\.volume, refreshedVolume)
            syncDisplayedVolume(with: refreshedVolume)
            updateIfChanged(\.speakerName, refreshedName)
            updateIfChanged(\.speakerModel, refreshedModel)

            if refreshedStatus == .powerOn {
                let refreshedIsPlaying = (try? await speaker.getIsPlaying()) ?? false
                guard self.speaker === speaker else { return }
                updateIfChanged(\.isPlaying, refreshedIsPlaying)
                if refreshedIsPlaying {
                    let refreshedNowPlaying = try? await speaker.getNowPlayingInfo()
                    guard self.speaker === speaker else { return }
                    updateIfChanged(\.nowPlaying, refreshedNowPlaying)
                } else {
                    updateIfChanged(\.nowPlaying, nil)
                }
            } else {
                updateIfChanged(\.isPlaying, false)
                updateIfChanged(\.nowPlaying, nil)
            }

            markConnectionHealthy(for: speaker)
        } catch {
            guard self.speaker === speaker else { return }
            if await speaker.testConnection() {
                markConnectionHealthy(for: speaker)
            } else {
                recordConnectionFailure(for: speaker)
            }
        }
    }

    private func markConnectionHealthy(for speaker: KEFSpeakerClient, stopDiscovery: Bool = false) {
        guard self.speaker === speaker else { return }

        consecutiveRefreshFailures = 0
        isConnected = true
        isReconnecting = false
        currentHost = speaker.host
        lastConnectedHost = speaker.host
        connectionError = nil
        if stopDiscovery {
            discovery.stopDiscovery()
        }
    }

    private func recordConnectionFailure(for speaker: KEFSpeakerClient) {
        guard self.speaker === speaker else { return }

        consecutiveRefreshFailures += 1

        if consecutiveRefreshFailures >= 3 || !isConnected {
            isConnected = false
            isReconnecting = true
            connectionError = "Reconnecting to speaker..."
        }
    }

    private func updateIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, Value>, _ newValue: Value) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }

    /// Poll rapidly until the expected condition is met, or timeout.
    private func waitForState(timeout: Duration = .seconds(8), condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
            if condition() { return }
        }
    }

    // MARK: - Actions

    private func runSpeakerAction(_ action: @escaping (KEFSpeakerClient) async throws -> Void) {
        guard let speaker else { return }

        Task {
            do {
                try await action(speaker)
            } catch {
                await handleSpeakerActionError(error, for: speaker)
            }
        }
    }

    private func runBusySpeakerAction(_ action: @escaping (KEFSpeakerClient) async throws -> Void) {
        guard let speaker else { return }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await action(speaker)
            } catch {
                await handleSpeakerActionError(error, for: speaker)
            }
        }
    }

    private func handleSpeakerActionError(_ error: Error, for speaker: KEFSpeakerClient) async {
        guard self.speaker === speaker else { return }

        if await speaker.testConnection() {
            connectionError = error.localizedDescription
            await refresh()
        } else {
            recordConnectionFailure(for: speaker)
        }
    }

    func commitVolume(_ newVolume: Int) {
        commitVolume(newVolume, applyingStepPolicy: true)
    }

    private func commitVolume(_ newVolume: Int, applyingStepPolicy: Bool) {
        let clampedVolume = applyingStepPolicy
            ? volumePolicy.normalizedVolume(newVolume)
            : VolumePolicy.clampedVolume(newVolume)
        if clampedVolume > 0 {
            volumeBeforeMediaKeyMute = nil
        }
        volume = clampedVolume
        displayedVolume = clampedVolume
        pendingCommittedVolume = clampedVolume
        pendingVolumeResetTask?.cancel()
        pendingVolumeResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            if self.pendingCommittedVolume == clampedVolume {
                self.clearPendingVolume()
            }
        }

        guard let speaker else { return }
        if !isVolumeHUDSuppressed {
            volumeHUD.show(
                title: volumeHUDTitle,
                volume: clampedVolume
            )
        }
        Task {
            do {
                try await speaker.setVolume(clampedVolume)
                try? await Task.sleep(for: .milliseconds(400))
                await refresh()
            } catch {
                guard self.speaker === speaker else { return }
                clearPendingVolume()
                await handleSpeakerActionError(error, for: speaker)
            }
        }
    }

    private func adjustVolume(by delta: Int) {
        let direction = delta.signum()
        guard direction != 0 else { return }
        commitVolume(volumePolicy.nextVolume(from: displayedVolume, direction: direction))
    }

    private func toggleMute() {
        let result = VolumePolicy.muteToggle(
            from: displayedVolume,
            restoreVolume: volumeBeforeMediaKeyMute
        )
        volumeBeforeMediaKeyMute = result.restoreVolume

        if result.targetVolume != displayedVolume {
            commitVolume(result.targetVolume, applyingStepPolicy: false)
        }
    }

    private var volumeHUDTitle: String {
        speakerModel.isEmpty ? speakerName : speakerModel
    }

    func setSource(_ newSource: SpeakerSource) {
        let oldSource = source
        clearPendingVolume()

        runBusySpeakerAction { speaker in
            try await speaker.setSource(newSource)
            await self.waitForState { self.source == newSource || self.source != oldSource }
            // Speaker may take a moment to settle the per-source volume
            try? await Task.sleep(for: .milliseconds(500))
            await self.refresh()
        }
    }

    func togglePower() {
        let wasPoweredOn = status == .powerOn

        runBusySpeakerAction { speaker in
            if wasPoweredOn {
                try await speaker.shutdown()
                await self.waitForState { self.status == .standby }
            } else {
                try await speaker.powerOn()
                await self.waitForState { self.status == .powerOn }
            }
        }
    }

    func togglePlayPause() {
        let wasPlaying = isPlaying

        runBusySpeakerAction { speaker in
            try await speaker.togglePlayPause()
            await self.waitForState(timeout: .seconds(4)) { self.isPlaying != wasPlaying }
        }
    }

    func nextTrack() {
        runSpeakerAction { speaker in
            try await speaker.nextTrack()
            try? await Task.sleep(for: .milliseconds(500))
            await self.refresh()
        }
    }

    func previousTrack() {
        runSpeakerAction { speaker in
            try await speaker.previousTrack()
            try? await Task.sleep(for: .milliseconds(500))
            await self.refresh()
        }
    }

    // MARK: - Volume reconciliation

    /// Keep the UI optimistic after a local volume change. Speakers can report
    /// their old volume for a short period after `setVolume`; this prevents the
    /// slider and HUD from bouncing backward while the command is settling.
    private func syncDisplayedVolume(with remoteVolume: Int) {
        if let pendingCommittedVolume {
            if remoteVolume == pendingCommittedVolume {
                clearPendingVolume()
            } else {
                displayedVolume = pendingCommittedVolume
            }
        } else {
            displayedVolume = remoteVolume
            if remoteVolume > 0 {
                volumeBeforeMediaKeyMute = nil
            }
        }
    }

    private func clearPendingVolume(keepDisplayedVolume: Bool = true) {
        pendingCommittedVolume = nil
        pendingVolumeResetTask?.cancel()
        pendingVolumeResetTask = nil
        if keepDisplayedVolume {
            displayedVolume = volume
        }
    }

    // MARK: - Media keys

    private func handleVolumeKey(_ delta: Int) -> Bool {
        guard shouldRouteVolumeKeysToSpeaker else { return false }
        adjustVolume(by: delta)
        return true
    }

    private func handleMuteKey() -> Bool {
        guard shouldRouteVolumeKeysToSpeaker else { return false }
        toggleMute()
        return true
    }

    private var shouldRouteVolumeKeysToSpeaker: Bool {
        guard isConnected, status == .powerOn else { return false }

        switch volumeKeyRoutingMode {
        case .mac:
            return false
        case .auto:
            return source.usesPlaybackStateForVolumeRouting ? isPlaying : true
        case .speaker:
            return true
        }
    }

    private func migrateLegacyVolumeKeyPreference() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "volumeKeyRoutingMode") == nil,
              let legacyValue = defaults.object(forKey: "useVolumeKeys") as? Bool else {
            return
        }

        volumeKeyRoutingMode = legacyValue ? .auto : .mac
    }

    // MARK: - Wake-on-LAN

    var speakerMAC: String? {
        if let currentHost,
           let mac = discovery.speakers.first(where: { $0.host == currentHost })?.macAddress {
            return mac
        }

        if let mac = discovery.speakers.first(where: { $0.macAddress != nil })?.macAddress {
            return mac
        }

        return nil
    }

    func wakeSpeaker() {
        guard let mac = speakerMAC else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            _ = sendWakeOnLAN(macAddress: mac)
            for _ in 0..<20 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if let host = currentHost ?? preferredWakeHost {
                    let api = KEFSpeakerAPI(host: host)
                    if await api.testConnection() {
                        connect(to: host)
                        return
                    }
                }
            }
            connectionError = "Speaker did not wake up"
        }
    }

    private var preferredWakeHost: String? {
        if !lastConnectedHost.isEmpty {
            return lastConnectedHost
        }

        return discovery.speakers.first?.host
    }
}

private extension SpeakerSource {
    var usesPlaybackStateForVolumeRouting: Bool {
        self == .wifi || self == .bluetooth
    }
}
