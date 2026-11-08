import AppKit
import SwiftUI

// The real FloatingPanelController is linked below. Stub only its irrelevant content view.
struct PanelView: View {
    let store: ProjectStore
    let onReduce: () -> Void
    let onRestore: () -> Void
    let onSettings: () -> Void
    let onBeginEditing: () -> Void
    let onEndEditing: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    let noteUndoManager: UndoManager?
    var body: some View { Color.clear }
}
@main
struct PanelGeometryTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw NSError(domain: "PanelGeometryTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No usable screen"])
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Relais-Geometry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(directory: directory)
        precondition(store.completeInitialSetup(labels: PositionLabels(left: "Équipe Alpha", right: "Équipe Bêta")))
        store.setPanelVisible(false) // Test windows never become visible.
        store.setWindowFrame(SavedWindowFrame(x: 100000, y: -100000, width: 248, height: 400))
        let controller = FloatingPanelController(store: store, onSettings: {})
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }
        check(!controller.panel.isVisible, "Fixture remains invisible")
        check(NSScreen.screens.contains { $0.visibleFrame.contains(controller.panel.frame) }, "Far-off saved frame recovers onto an available screen")
        check(controller.panel.frame.width == 248, "Restored width stays compact")
        let top = bounds.maxY - 20
        controller.panel.setFrame(NSRect(x: bounds.maxX-268, y: top-178, width: 248, height: 178), display: false)
        let projectNames = ["Projet Alpha", "Projet Bêta", "Projet Gamma", "Projet Delta"]
        for index in 0..<5 { _ = store.addProject(name: projectNames[index % projectNames.count]) }
        controller.resizeToFit()
        check(abs(controller.panel.frame.maxY - top) < 0.01, "Adding projects preserves top anchor")
        check(controller.panel.frame.height == min(66+5*104, bounds.height), "Five projects use a safe initial size estimate")
        controller.updateContentHeight(650)
        check(controller.panel.frame.height == min(650, bounds.height), "Measured note content expands panel")
        check(abs(controller.panel.frame.maxY - top) < 0.01, "Notes preserve top anchor")

        let firstProjectID = store.state.projects[0].id
        store.setPosition(id: firstProjectID, position: .right)
        store.setCustomLabels(id: firstProjectID, labels: PositionLabels(left: "Étape Alpha", right: "Étape Bêta"))
        for text in ["En attente de validation", "Tests à effectuer", "Documentation à compléter"] {
            _ = store.addNote(projectID: firstProjectID, text: text)
        }
        _ = store.setNotePinned(projectID: firstProjectID,
                               noteID: store.state.projects[0].notes[1].id, isPinned: true)
        let preservedProjects = store.state.projects
        let expandedFrame = controller.panel.frame
        let originalPanel = controller.panel
        let originalContent = controller.panel.contentView
        let originalUndoManager = controller.panel.undoManager
        check(controller.setMode(.compact), "Reduction saved successfully")
        check(controller.panel === originalPanel && controller.panel.contentView === originalContent,
              "Reduction reuses panel and hosting view")
        check(controller.panel.frame.width == 148 && controller.panel.frame.height == 36,
              "Compact dimensions are 148 by 36")
        check(controller.panel.frame.minX == expandedFrame.minX && controller.panel.frame.maxY == expandedFrame.maxY,
              "First reduction preserves top-left anchor")
        check(!controller.panel.isVisible && !store.state.panelVisible, "Changing mode does not unhide hidden window")
        check(controller.panel.level == .floating && controller.panel.styleMask.contains(.nonactivatingPanel)
              && controller.panel.collectionBehavior.contains(.canJoinAllSpaces)
              && controller.panel.collectionBehavior.contains(.fullScreenAuxiliary),
              "Compact mode retains floating nonactivation and Spaces configuration")
        controller.panel.setFrameOrigin(NSPoint(x: bounds.minX + 30, y: bounds.maxY - 100))
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: controller.panel))
        let compactFrame = controller.panel.frame
        check(store.state.compactWindowFrame?.x == compactFrame.minX
              && store.state.compactWindowFrame?.y == compactFrame.minY,
              "Moving compact panel persists its independent frame")
        check(controller.setMode(.expanded) && controller.panel.frame == expandedFrame,
              "Expanded mode restores its own frame and measured note height")
        check(controller.setMode(.compact) && controller.panel.frame == compactFrame,
              "Compact mode restores its separate moved frame")
        var cycleSuccess = true
        for _ in 0..<20 {
            cycleSuccess = controller.setMode(.expanded) && controller.setMode(.compact) && cycleSuccess
        }
        check(cycleSuccess && store.state.projects == preservedProjects,
              "Twenty mode cycles preserve projects positions labels notes pins and order")
        check(controller.panel === originalPanel && controller.panel.contentView === originalContent
              && controller.panel.undoManager === originalUndoManager,
              "Twenty mode cycles preserve panel hosting view and undo manager")
        let finalCycleFrame = controller.panel.frame
        var mainQueueDrained = false
        DispatchQueue.main.async { mainQueueDrained = true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(mainQueueDrained && controller.mode == .compact && store.state.panelMode == .compact
              && controller.panel.frame == finalCycleFrame && store.state.projects == preservedProjects,
              "Deferred mode notifications preserve the final mode frame and projects after the main queue drains")
        controller.updateContentHeight(720)
        check(controller.panel.frame.height == 36 && controller.panel.frame == compactFrame,
              "Note height measurements never expand or move the compact panel")
        controller.panel.setFrameOrigin(NSPoint(x: 100000, y: -100000))
        controller.resizeToFit()
        check(NSScreen.screens.contains { $0.visibleFrame.contains(controller.panel.frame) }
              && controller.panel.frame.width == 148 && controller.panel.frame.height == 36,
              "Offscreen compact frame recovers onto an available screen")
        check(controller.setMode(.expanded) && controller.panel.frame.height == min(720, bounds.height),
              "Restoration uses the updated natural note height")
        check(abs(controller.panel.frame.maxY - expandedFrame.maxY) < 0.01,
              "Restoring expanded panel keeps its saved top anchor after note height changes")

        controller.updateContentHeight(100000)
        check(controller.panel.frame.height == bounds.height, "Measured note content capped to screen")
        controller.updateContentHeight(.nan)
        check(controller.panel.frame.height == bounds.height, "Invalid measurement ignored")
        for index in 5..<80 { _ = store.addProject(name: projectNames[index % projectNames.count]) }
        controller.resizeToFit()
        check(controller.panel.frame.height == bounds.height, "Long list capped to actual screen")
        check(bounds.contains(controller.panel.frame), "Long list panel fully contained")
        for project in store.state.projects { store.deleteProject(id: project.id) }
        let oldTop = controller.panel.frame.maxY
        controller.updateContentHeight(178)
        controller.resizeToFit()
        check(controller.panel.frame.height == 178, "Deleting list restores compact empty height")
        check(abs(controller.panel.frame.maxY - oldTop) < 0.01, "Deleting projects preserves top anchor")
        controller.panel.setFrameOrigin(NSPoint(x: -100000, y: 100000))
        controller.resizeToFit()
        check(NSScreen.screens.contains { $0.visibleFrame.contains(controller.panel.frame) }, "Off-screen resize recovers accessible position on some current screen")
        let saved = ProjectStore(directory: directory)
        check(saved.state.windowFrame?.x == controller.panel.frame.minX && saved.state.windowFrame?.y == controller.panel.frame.minY,
              "Recovered geometry persisted")
        check(!controller.panel.isVisible, "No test window shown")
        _ = store.addProject(name: "Projet Alpha")
        _ = store.addNote(projectID: store.state.projects[0].id, text: "En attente de validation")
        check(controller.setMode(.compact), "Final compact mode saved before relaunch simulation")
        let compactBeforeReload = controller.panel.frame
        let reloadedStore = ProjectStore(directory: directory)
        let reloaded = FloatingPanelController(store: reloadedStore, onSettings: {})
        check(!reloadedStore.needsInitialSetup && reloaded.mode == .compact,
              "Relaunch retains compact mode without repeating setup")
        check(reloaded.panel.frame == compactBeforeReload && !reloaded.panel.isVisible,
              "Relaunch restores compact frame and hidden preference")
        check(reloadedStore.state.projects == store.state.projects && reloadedStore.state.projects[0].notes.count == 1,
              "Relaunch retains note content while reduced")
        print("PASS: \(count) actual FloatingPanelController geometry assertions (available screens, simulated offscreen movement).")
    }
}
