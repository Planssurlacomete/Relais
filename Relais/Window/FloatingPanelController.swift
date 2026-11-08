import AppKit
import Combine
import SwiftUI

/// A utility panel may receive keyboard input without activating the application
/// that owns it. It never becomes the main window of the user's workspace.
final class FloatingPanel: NSPanel {
    private let noteUndoManager = UndoManager()
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var undoManager: UndoManager? { noteUndoManager }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    private let store: ProjectStore
    private var subscriptions = Set<AnyCancellable>()
    private var updatingFrame = false
    private var displayedMode: PanelMode
    private var measuredContentHeight: CGFloat?

    init(store: ProjectStore, onSettings: @escaping () -> Void) {
        self.store = store
        displayedMode = store.state.panelMode
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 248, height: 178),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        panel.title = "Relais"
        panel.identifier = NSUserInterfaceItemIdentifier("relais.floating-panel")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
            .canJoinAllApplications
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        let content = NSHostingView(rootView: PanelView(
            store: store,
            onReduce: { [weak self] in _ = self?.setMode(.compact) },
            onRestore: { [weak self] in _ = self?.setMode(.expanded) },
            onSettings: onSettings,
            onBeginEditing: { [weak self] in self?.panel.makeKey() },
            onEndEditing: { [weak self] in self?.panel.resignKey() },
            onContentHeightChange: { [weak self] height in self?.updateContentHeight(height) },
            noteUndoManager: panel.undoManager
        ))
        // The controller owns both sizes; stale expanded-view minimums must
        // never prevent the same window from becoming a compact pill.
        content.sizingOptions = []
        panel.contentView = content
        restoreFrame()
        // Only layout-affecting changes resize the panel. No polling or timers.
        store.$state.map { $0.projects }.removeDuplicates()
            .dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizeToFit() }
            }.store(in: &subscriptions)
        store.$persistenceError.map { $0 != nil }.removeDuplicates()
            .dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizeToFit() }
            }.store(in: &subscriptions)
        store.$state.map { $0.panelMode }.removeDuplicates()
            .dropFirst().sink { [weak self] mode in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.store.state.panelMode == mode else { return }
                    self.applyMode(mode)
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        if store.state.panelVisible { show() }
    }

    var isVisible: Bool { panel.isVisible }
    var mode: PanelMode { displayedMode }
    var canChangeMode: Bool { panel.attachedSheet == nil }

    func show() {
        resizeToFit()
        panel.orderFrontRegardless()
        store.setPanelVisible(true)
    }

    func hide() {
        panel.orderOut(nil)
        store.setPanelVisible(false)
    }

    func toggle() { isVisible ? hide() : show() }

    @discardableResult
    func setMode(_ mode: PanelMode) -> Bool {
        guard canChangeMode else { return false }
        guard mode != displayedMode else { return true }
        persistFrame()
        guard store.setPanelMode(mode) else { return false }
        applyMode(mode)
        return true
    }

    private func applyMode(_ mode: PanelMode) {
        guard mode != displayedMode else { return }
        let previous = panel.frame
        displayedMode = mode
        // A mode starts at the same top-left corner until it has its own saved
        // position. Afterwards each mode restores exactly its last placement.
        let destination = savedFrame(for: mode).map(rect) ?? previous
        applyFrame(destination, on: bestScreen(for: destination))
        if mode == .compact { panel.resignKey() }
    }

    private var width: CGFloat { displayedMode == .compact ? 148 : 248 }

    private var desiredHeight: CGFloat {
        if displayedMode == .compact { return 36 }
        if let measuredContentHeight { return max(178, measuredContentHeight) }
        // Estimate only until SwiftUI reports its natural content size.
        let body = max(112, store.state.projects.reduce(CGFloat.zero) { height, project in
            height + 104 + CGFloat(project.notes.count) * 32
        })
        return 66 + body + (store.persistenceError == nil ? 0 : 58)
    }

    func updateContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0,
              measuredContentHeight.map({ abs($0 - height) > 0.5 }) ?? true else { return }
        measuredContentHeight = height
        resizeToFit()
    }

    private func bestScreen(for rect: NSRect) -> NSScreen? {
        NSScreen.screens.max {
            let a = $0.visibleFrame.intersection(rect)
            let b = $1.visibleFrame.intersection(rect)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }.flatMap { screen in
            screen.visibleFrame.intersects(rect) ? screen : NSScreen.main
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func restoreFrame() {
        if let saved = savedFrame(for: displayedMode) ?? savedFrame(for: displayedMode == .compact ? .expanded : .compact) {
            let frame = rect(saved)
            applyFrame(frame, on: bestScreen(for: frame))
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            applyFrame(NSRect(x: visible.maxX - width - 16,
                              y: visible.maxY - desiredHeight - 16,
                              width: width, height: desiredHeight), on: screen)
        }
    }

    private func savedFrame(for mode: PanelMode) -> SavedWindowFrame? {
        mode == .compact ? store.state.compactWindowFrame : store.state.windowFrame
    }

    private func rect(_ frame: SavedWindowFrame) -> NSRect {
        NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private func applyFrame(_ rect: NSRect, on screen: NSScreen?) {
        guard let screen else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let height = min(desiredHeight, bounds.height)
        let safeX = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        // Anchor at the old top edge when projects are added or removed.
        let safeY = min(max(rect.maxY - height, bounds.minY), bounds.maxY - height)
        updatingFrame = true
        panel.setFrame(NSRect(x: safeX, y: safeY, width: width, height: height), display: true)
        updatingFrame = false
        persistFrame()
    }

    func resizeToFit() { applyFrame(panel.frame, on: bestScreen(for: panel.frame)) }

    @objc private func screensChanged() { resizeToFit() }

    private func persistFrame() {
        guard !updatingFrame else { return }
        let frame = panel.frame
        store.setWindowFrame(SavedWindowFrame(x: frame.minX, y: frame.minY,
                                             width: frame.width, height: frame.height), mode: displayedMode)
    }

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowDidChangeScreen(_ notification: Notification) {
        if !updatingFrame { resizeToFit() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
}
