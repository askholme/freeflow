import SwiftUI
import AppKit

/// Non-activating `NSPanel` for the Re-run Last Recording profile
/// chooser. Uses the same `.borderless, .nonactivatingPanel` style
/// mask as the menu-bar toast overlays in `RecordingOverlay.swift`
/// (so it never activates the owning application or steals Dock
/// focus from the previously frontmost app) but, unlike those purely
/// decorative toasts, this panel explicitly becomes key so it can
/// receive arrow/Return/Escape keyDown events directly through the
/// normal AppKit responder chain.
///
/// Escape is also handled globally through the existing
/// `GlobalShortcutBackend.onEscapeKeyPressed` event-tap callback
/// (`AppState.handleEscapeKeyPress`), which — being a head-inserted
/// system-wide tap — observes and consumes the key before this
/// panel's own `keyDown` would ever see it. The panel's own Escape
/// handling below is a redundant safety net for the (rare) case the
/// event tap is unavailable, e.g. missing Accessibility/Input
/// Monitoring permission.
final class ReprocessChooserPanel: NSPanel {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: // Up arrow
            onArrowUp?()
        case 125: // Down arrow
            onArrowDown?()
        case 36, 76: // Return / keypad Enter
            onConfirm?()
        case 53: // Escape
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

/// Row height and maximum simultaneously visible rows for the
/// profile list. Shared between the SwiftUI content's `ScrollView`
/// frame and `ReprocessProfileChooserManager`'s panel-height
/// calculation so the two never drift out of sync — the Language
/// Profile catalog supports far more entries than comfortably fit in
/// a fixed-height panel (up to ~30 languages), so beyond
/// `reprocessChooserMaxVisibleRows` profiles the list scrolls instead
/// of clipping.
private let reprocessChooserRowHeight: CGFloat = 34
private let reprocessChooserMaxVisibleRows = 8

/// Backing `ObservableObject` for the chooser's SwiftUI content. Kept
/// separate from `AppState` so the panel's presentation is a thin,
/// independently testable-by-inspection layer over the pure
/// `ReprocessProfileChooserState` reducer in `ReprocessLastRecording.swift`.
private final class ReprocessProfileChooserHostingState: ObservableObject {
    @Published var profiles: [LanguageProfile] = []
    @Published var selectedIndex: Int = 0
}

private struct ReprocessProfileChooserContentView: View {
    @ObservedObject var state: ReprocessProfileChooserHostingState

    private var listHeight: CGFloat {
        CGFloat(min(state.profiles.count, reprocessChooserMaxVisibleRows)) * reprocessChooserRowHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reprocess With…")
                .font(.headline)
                .foregroundStyle(.white)

            // Bounded, scrollable list: with more eligible profiles
            // than fit in `reprocessChooserMaxVisibleRows`, the list
            // scrolls instead of clipping content (including the
            // keyboard-selected row) with no way to reach it.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(state.profiles.enumerated()), id: \.offset) { index, profile in
                            HStack {
                                Text(profile.name)
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(index == state.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
                            )
                            .id(index)
                        }
                    }
                }
                .frame(height: listHeight)
                .onAppear {
                    proxy.scrollTo(state.selectedIndex, anchor: .center)
                }
                .onChange(of: state.selectedIndex) { newIndex in
                    // Keyboard arrow navigation must keep the
                    // currently selected row visible even once the
                    // user has navigated past the initially visible
                    // window.
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }

            Text("↑↓ to navigate · Return to confirm · Esc to cancel")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
        .frame(minWidth: 260, alignment: .leading)
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Owns the lifecycle of the non-activating chooser panel. `AppState`
/// wires `onArrowUp`/`onArrowDown`/`onConfirm`/`onCancel` to route
/// through the pure `ReprocessProfileChooser` reducer so the panel
/// itself contains no eligibility, filtering, or reprocessing logic.
final class ReprocessProfileChooserManager {
    private var panel: ReprocessChooserPanel?
    private let hostingState = ReprocessProfileChooserHostingState()

    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    func show(profiles: [LanguageProfile], selectedIndex: Int) {
        DispatchQueue.main.async {
            self.hostingState.profiles = profiles
            self.hostingState.selectedIndex = selectedIndex
            if self.panel == nil {
                self.presentPanel()
            }
        }
    }

    func updateSelection(_ index: Int) {
        DispatchQueue.main.async {
            self.hostingState.selectedIndex = index
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.panel?.orderOut(nil)
            self.panel = nil
        }
    }

    /// Fixed chrome (header line, hint line, spacing, padding)
    /// surrounding the scrollable profile list, in points. Kept in
    /// sync with `ReprocessProfileChooserContentView`'s `VStack`
    /// layout (16pt padding top+bottom, two 8pt inter-section
    /// spacings, a ~20pt header line, a ~14pt hint line) plus a small
    /// safety margin, so the panel is sized tall enough that the
    /// `ScrollView` never gets squeezed below its own intended
    /// `listHeight` and clips the header/hint text at the edges.
    /// Exact on-screen fit still depends on real font metrics and
    /// remains part of manual chooser-interaction verification.
    private static let chromeHeight: CGFloat = 16 + 16 + 8 + 8 + 20 + 14 + 16

    /// Panel height that comfortably fits the header, the hint line,
    /// and up to `reprocessChooserMaxVisibleRows` profile rows — for
    /// more profiles than that, the content view's `ScrollView` (sized
    /// to the same `reprocessChooserMaxVisibleRows` cap) scrolls
    /// instead of the panel growing unboundedly tall.
    private static func panelHeight(forProfileCount count: Int) -> CGFloat {
        let visibleRows = max(1, min(count, reprocessChooserMaxVisibleRows))
        return chromeHeight + CGFloat(visibleRows) * reprocessChooserRowHeight
    }

    private func presentPanel() {
        let width: CGFloat = 320
        let height = Self.panelHeight(forProfileCount: hostingState.profiles.count)
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screenFrame.midX - width / 2, y: screenFrame.midY - height / 2)
        let panel = ReprocessChooserPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.onArrowUp = { [weak self] in self?.onArrowUp?() }
        panel.onArrowDown = { [weak self] in self?.onArrowDown?() }
        panel.onConfirm = { [weak self] in self?.onConfirm?() }
        panel.onCancel = { [weak self] in self?.onCancel?() }

        let hosting = NSHostingView(rootView: ReprocessProfileChooserContentView(state: hostingState))
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        panel.contentView = hosting

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}
