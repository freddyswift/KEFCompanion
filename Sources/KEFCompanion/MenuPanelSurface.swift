import AppKit
import SwiftUI

struct MenuPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(MenuPanelWindowSizer())
    }
}

extension View {
    func menuPanelSurface() -> some View {
        modifier(MenuPanelSurface())
    }
}

enum PanelColors {
    static let background = Color(nsColor: .controlBackgroundColor)
    static let settingsBackground = Color(nsColor: .windowBackgroundColor)
    static let sectionFill = Color(nsColor: .controlBackgroundColor).opacity(0.40)
    static let sectionStroke = Color(nsColor: .separatorColor).opacity(0.22)
    static let controlFill = Color(nsColor: .controlBackgroundColor).opacity(0.70)
    static let rowFill = Color(nsColor: .separatorColor).opacity(0.07)
}

enum MenuPanelLayout {
    static let width: CGFloat = 336
}

private struct MenuPanelWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> SizingView {
        SizingView()
    }

    func updateNSView(_ nsView: SizingView, context: Context) {
        nsView.scheduleWindowResize()
    }

    final class SizingView: NSView {
        private var isResizeScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleWindowResize()
        }

        override func layout() {
            super.layout()
            scheduleWindowResize()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            scheduleWindowResize()
        }

        func scheduleWindowResize() {
            guard !isResizeScheduled else { return }
            isResizeScheduled = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isResizeScheduled = false
                self.resizeWindowIfNeeded()
            }
        }

        private func resizeWindowIfNeeded() {
            guard let window, bounds.width > 0, bounds.height > 0 else { return }
            guard let contentView = window.contentView else { return }

            contentView.layoutSubtreeIfNeeded()
            let currentContentSize = contentView.bounds.size
            let fittingSize = contentView.fittingSize
            let measuredSize = bounds.size

            let targetHeight = fittingSize.height > currentContentSize.height + 0.5
                ? fittingSize.height
                : measuredSize.height
            let targetContentSize = NSSize(width: ceil(measuredSize.width), height: ceil(targetHeight))
            guard targetContentSize.width.isFinite, targetContentSize.height.isFinite else { return }

            guard abs(currentContentSize.width - targetContentSize.width) > 0.5 ||
                  abs(currentContentSize.height - targetContentSize.height) > 0.5 else {
                return
            }

            let targetFrameSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: targetContentSize)
            ).size

            var frame = window.frame
            let topEdge = frame.maxY
            frame.size = targetFrameSize
            frame.origin.y = topEdge - frame.height

            window.setFrame(frame, display: true, animate: false)
        }
    }
}
