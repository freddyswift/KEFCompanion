import SwiftUI

enum SettingsMetrics {
    static let labelWidth: CGFloat = 82
    static let segmentedWidth: CGFloat = 178
    static let stepInputWidth: CGFloat = 48
}

struct SettingsControlRow<Control: View>: View {
    private let title: String
    private let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: SettingsMetrics.labelWidth, alignment: .leading)

            control
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 34)
    }
}
