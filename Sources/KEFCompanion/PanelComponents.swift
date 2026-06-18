import SwiftUI

/// Reusable settings group. It intentionally keeps styling local to the app
/// rather than relying on a full design system, because the entire UI surface is
/// a compact menu-bar utility.
struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    let minHeight: CGFloat?
    @ViewBuilder var content: Content

    init(
        title: String,
        systemImage: String,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            content

            if minHeight != nil {
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .panelMaterialCardBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous),
            fillOpacity: 0.42,
            strokeOpacity: 0.72,
            lineWidth: 1.5
        )
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 1)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }
}

/// Small status row used across onboarding, settings, and disconnected states.
/// The accessory slot keeps rows visually consistent while allowing buttons,
/// progress indicators, or no trailing content.
struct StatusRow<Accessory: View>: View {
    let title: String
    let detail: String?
    let systemImage: String
    let tint: Color
    @ViewBuilder var accessory: Accessory

    init(
        title: String,
        detail: String?,
        systemImage: String,
        tint: Color,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
    }

    init(title: String, detail: String?, systemImage: String, tint: Color) where Accessory == EmptyView {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = EmptyView()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PanelColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            accessory
        }
    }
}
