import SwiftUI

struct VolumeStepSettingsSection: View {
    @EnvironmentObject private var appState: AppState

    @State private var volumeStepField = ""
    @FocusState private var isVolumeStepFocused: Bool

    var body: some View {
        SettingsSection(title: "Volume Steps", systemImage: "speaker.wave.2") {
            SettingsControlRow("Mode") {
                Picker("Volume control", selection: fixedVolumeStepsBinding) {
                    Text("Any Value").tag(false)
                    Text("Fixed Steps").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: SettingsMetrics.segmentedWidth)
            }

            if appState.useFixedVolumeSteps {
                volumeStepSizeRow
            }
        }
        .onAppear {
            volumeStepField = "\(appState.volumeStepSize)"
        }
        .onChange(of: isVolumeStepFocused) { oldValue, newValue in
            if oldValue && !newValue {
                commitVolumeStepField()
            }
        }
        .onChange(of: appState.volumeStepSize) { _, newValue in
            volumeStepField = "\(newValue)"
        }
    }

    private var volumeStepSizeRow: some View {
        SettingsControlRow("Step size") {
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
                .frame(width: SettingsMetrics.stepInputWidth)
                .focused($isVolumeStepFocused)
                .onSubmit { commitVolumeStepField() }
                .onChange(of: volumeStepField) { _, newValue in
                    updateVolumeStepField(newValue)
                }

            Stepper("Step size", value: volumeStepSizeBinding, in: appState.allowedVolumeStepRange)
                .labelsHidden()
                .help("Change step size")
        }
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
        isVolumeStepFocused = false
    }
}
