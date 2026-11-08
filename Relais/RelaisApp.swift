import AppKit
import Combine
import ServiceManagement
import SwiftUI

private final class WelcomeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@main
enum RelaisMain {
    @MainActor static func main() {
#if !RELAIS_TESTING
        // The distributed app has no command-line control or fixture interface.
        guard !ProcessInfo.processInfo.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) else {
            fputs("Relais ne prend pas en charge les options de ligne de commande.\n", stderr)
            exit(64)
        }
#endif
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var store: ProjectStore!
    private var login: LoginItemController!
    private var floating: FloatingPanelController?
    private var statusItem: NSStatusItem!
    private var welcomeWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var visibilityItem: NSMenuItem!
    private var modeItem: NSMenuItem!
    private var loginItem: NSMenuItem!
#if RELAIS_TESTING
    private var smokeDirectory: URL?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
#if RELAIS_TESTING
        // This code is absent from release builds. Smoke tests use the app's own
        // sandbox temporary directory, never the user's project store.
        let args = ProcessInfo.processInfo.arguments
        var directory: URL?
        if args.contains("--smoke-test") || args.contains("--notes-ui-test") || args.contains("--setup-ui-test") {
            let fixture = FileManager.default.temporaryDirectory
                .appendingPathComponent("RelaisSmoke-\(UUID().uuidString)", isDirectory: true)
            smokeDirectory = fixture
            directory = fixture
        } else if let index = args.firstIndex(of: "--data-directory"), args.indices.contains(index + 1) {
            directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        }
        store = ProjectStore(directory: directory)
        if args.contains("--setup-ui-test") && args.contains("--setup-write-failure") {
            do {
                // Insert the obstacle only after the fresh store has loaded. This
                // fixture is confined to the unique sandbox test directory above.
                let base = store.dataURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let canary = base.appendingPathComponent("save-canary.txt")
                try Data("Données synthétiques de contrôle.\n".utf8).write(to: canary, options: .atomic)
                try FileManager.default.createSymbolicLink(at: store.dataURL, withDestinationURL: canary)
                print("TEST_WRITE_FAILURE_FIXTURE=enabled")
            } catch {
                fputs("La fixture isolée d’échec de sauvegarde n’a pas pu être créée.\n", stderr)
                exit(1)
            }
        }
        if args.contains("--notes-ui-test") {
            // The UI automation driver targets the foreground application for keys.
            // Only this disposable fixture uses a Dock identity; production and
            // the window smoke test retain the normal accessory activation policy.
            NSApp.setActivationPolicy(.regular)
            _ = store.completeInitialSetup(labels: PositionLabels(left: "Équipe Alpha", right: "Équipe Bêta"))
            _ = store.addProject(name: "Projet Alpha")
            _ = store.addProject(name: "Projet Bêta")
            if let screen = NSScreen.main {
                store.setWindowFrame(SavedWindowFrame(x: screen.visibleFrame.minX + 40,
                                                      y: screen.visibleFrame.maxY - 450,
                                                      width: 248, height: 300))
            }
        }
        if args.contains("--setup-ui-test") { NSApp.setActivationPolicy(.regular) }
        if args.contains("--notes-ui-test") || args.contains("--setup-ui-test") {
            print("TEST_DATA_DIRECTORY=\(store.dataURL.deletingLastPathComponent().path)")
            fflush(stdout)
        }
#else
        store = ProjectStore()
#endif
        login = LoginItemController()
        installMenuBar()
        if store.needsInitialSetup {
            showInitialSetup()
        } else {
            createFloatingPanelIfReady()
        }
#if RELAIS_TESTING
        if args.contains("--notes-ui-test") || args.contains("--setup-ui-test") {
            NSApp.activate(ignoringOtherApps: true)
        }
#endif
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshLogin),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
#if RELAIS_TESTING
        if args.contains("--smoke-test") {
            let setupChecks = runInitialSetupSmokeTest()
            runWindowSmokeTest(initialChecks: setupChecks)
        }
#endif
    }

    private func createFloatingPanelIfReady() {
        // Its geometry and visibility are persisted. Do not construct it before
        // initial setup, or a window event could create a premature state file.
        guard floating == nil, !store.needsInitialSetup else { return }
        floating = FloatingPanelController(store: store, onSettings: { [weak self] in
            self?.showPreferences()
        })
    }

    private func showInitialSetup() {
        guard store.needsInitialSetup else { return }
        if welcomeWindow == nil {
            let window = WelcomeWindow(
                contentRect: NSRect(x: 0, y: 0, width: 328, height: 300),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.title = "Bienvenue sur Relais"
            window.identifier = NSUserInterfaceItemIdentifier("relais.welcome")
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = .zero
            window.contentMinSize = .zero
            let content = NSHostingView(rootView: WelcomeView(
                store: store,
                onComplete: { [weak self] in self?.finishInitialSetup() },
                onContentHeightChange: { [weak self, weak window] height in
                    // Resize after SwiftUI's layout pass, including when a failed
                    // save adds an error message below the unchanged draft fields.
                    DispatchQueue.main.async {
                        guard let self, let window else { return }
                        self.resizeWelcomeWindow(window, contentHeight: height)
                    }
                }
            ).ignoresSafeArea())
            // SwiftUI reports the natural height explicitly below. Its automatic
            // AppKit minimum size must not reintroduce the hidden titlebar inset.
            content.sizingOptions = []
            window.contentView = content
            resizeWelcomeWindow(window, contentHeight: content.fittingSize.height)
            window.center()
            welcomeWindow = window
        }
        welcomeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resizeWelcomeWindow(_ window: NSWindow, contentHeight: CGFloat) {
        guard contentHeight.isFinite, contentHeight > 0,
              abs(window.frame.height - contentHeight) > 0.5 else { return }
        let frame = window.frame
        // The borderless welcome has no titlebar or reserved decoration area.
        window.setFrame(NSRect(x: frame.minX, y: frame.maxY - contentHeight,
                               width: 328, height: contentHeight), display: true)
    }

    private func finishInitialSetup() {
        guard !store.needsInitialSetup, !store.isDataUnavailable else { return }
        welcomeWindow?.orderOut(nil)
        welcomeWindow = nil
        createFloatingPanelIfReady()
        floating?.show()
    }

    private func installMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = RelaisIcon.templateImage(size: 18)
            button.toolTip = "Relais — passage de main"
            button.setAccessibilityLabel("Relais")
        }
        let menu = NSMenu(title: "Relais")
        menu.delegate = self
        visibilityItem = item("Masquer Relais", action: #selector(togglePanel), key: "")
        menu.addItem(visibilityItem)
        modeItem = item("Réduire Relais", action: #selector(togglePanelMode), key: "")
        menu.addItem(modeItem)
        menu.addItem(item("Réglages…", action: #selector(showPreferences), key: ","))
        menu.addItem(.separator())
        loginItem = item("Lancer à l’ouverture de session", action: #selector(toggleLogin), key: "")
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("À propos de Relais", action: #selector(showAbout), key: ""))
        menu.addItem(item("Quitter Relais", action: #selector(quit), key: "q"))
        statusItem.menu = menu
        // Text fields need the standard edit menu, also for the nonactivating panel.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Relais")
        appMenu.addItem(item("Quitter Relais", action: #selector(quit), key: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let edit = NSMenu(title: "Édition")
        edit.addItem(item("Annuler", action: #selector(undoEdit), key: "z"))
        let redo = item("Rétablir", action: #selector(redoEdit), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        for (title, selector, key) in [
            ("Couper", #selector(NSText.cut(_:)), "x"),
            ("Copier", #selector(NSText.copy(_:)), "c"),
            ("Coller", #selector(NSText.paste(_:)), "v"),
            ("Tout sélectionner", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    // A borderless nonactivating panel can lose its first responder when the
    // deleted button disappears. Route Undo to its persistent manager explicitly,
    // while keeping the standard text editor's own Undo/Redo during text entry.
    private var editingUndoManager: UndoManager? {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            return editor.undoManager
        }
        if preferencesWindow?.isKeyWindow == true || welcomeWindow?.isKeyWindow == true { return nil }
        return floating?.panel.undoManager
    }

    @objc private func undoEdit() { editingUndoManager?.undo() }
    @objc private func redoEdit() { editingUndoManager?.redo() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undoEdit) { return editingUndoManager?.canUndo == true }
        if menuItem.action == #selector(redoEdit) { return editingUndoManager?.canRedo == true }
        if menuItem.action == #selector(toggleLogin) { return !store.needsInitialSetup && !store.isDataUnavailable }
        if menuItem.action == #selector(togglePanelMode) {
            return !store.needsInitialSetup && !store.isDataUnavailable && floating?.canChangeMode == true
        }
        return true
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        login.refresh()
        visibilityItem.title = store.needsInitialSetup ? "Configurer Relais…" :
            (floating?.isVisible == true ? "Masquer Relais" : "Afficher Relais")
        modeItem.title = store.state.panelMode == .compact ? "Agrandir Relais" : "Réduire Relais"
        loginItem.state = login.requiresApproval ? .mixed : (login.isEnabled ? .on : .off)
        loginItem.toolTip = login.errorMessage ?? login.statusDescription
    }

    @objc private func togglePanel() {
        guard !store.needsInitialSetup else { showInitialSetup(); return }
        createFloatingPanelIfReady()
        floating?.toggle()
    }
    @objc private func togglePanelMode() {
        guard !store.needsInitialSetup else { showInitialSetup(); return }
        createFloatingPanelIfReady()
        guard let floating else { return }
        _ = floating.setMode(floating.mode == .compact ? .expanded : .compact)
    }
    @objc private func refreshLogin() { login.refresh() }
    @objc private func toggleLogin() {
        guard !store.needsInitialSetup, !store.isDataUnavailable else { showInitialSetup(); return }
        login.setEnabled(!(login.isEnabled || login.requiresApproval))
        if login.errorMessage != nil || SMAppService.mainApp.status == .requiresApproval {
            showPreferences()
        }
    }

    @objc private func showPreferences() {
        guard !store.needsInitialSetup else { showInitialSetup(); return }
        login.refresh()
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 390, height: 510),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.title = "Réglages de Relais"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView(store: store, login: login))
            window.appearance = NSAppearance(named: .darkAqua)
            window.center()
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Relais",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .credits: NSAttributedString(string:
                "Un projet, un interrupteur, deux positions.\n\n" +
                "Commutateur adapté de Saiyed-Tanvir — Uiverse (MIT).\n" +
                "La licence complète est incluse dans les ressources de l’application.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if store.needsInitialSetup {
            showInitialSetup()
        } else {
            createFloatingPanelIfReady()
            floating?.show()
        }
        return false
    }

#if RELAIS_TESTING
    private func runInitialSetupSmokeTest() -> [(String, Bool)] {
        var checks: [(String, Bool)] = [
            ("fresh state requires initial setup", store.needsInitialSetup),
            ("fresh welcome window is visible", welcomeWindow?.isVisible == true),
            ("fresh setup does not construct floating panel", floating == nil),
            ("fresh setup does not create projects", store.state.projects.isEmpty),
            ("welcome geometry does not write state", !FileManager.default.fileExists(atPath: store.dataURL.path))
        ]
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
        showPreferences()
        checks.append(("reopen and preferences keep incomplete setup in welcome",
                       welcomeWindow?.isVisible == true && floating == nil && preferencesWindow == nil))

        let form = WelcomeForm()
        checks.append(("welcome fields initially empty and submit disabled",
                       form.left.isEmpty && form.right.isEmpty && !form.canSubmit))
        form.left = "Équipe Alpha"
        checks.append(("missing second label disables submit", !form.canSubmit))
        form.left = "  Équipe   Alpha  "
        form.right = "éQUIPE Alpha"
        checks.append(("equivalent whitespace and case disables submit", !form.canSubmit))
        form.right = String(repeating: "x", count: StateLimits.maximumLabelBytes + 1)
        checks.append(("oversized label disables submit", !form.canSubmit))
        form.left = "Équipe Alpha"
        form.right = "Équipe Bêta"
        checks.append(("different accented Unicode labels enable submit", form.canSubmit))

        let failingDirectory = store.dataURL.deletingLastPathComponent()
            .appendingPathComponent("save-failure", isDirectory: true)
        let failingStore = ProjectStore(directory: failingDirectory)
        let failingForm = WelcomeForm()
        failingForm.left = "Équipe Alpha"
        failingForm.right = "Équipe Bêta"
        do {
            // The store starts fresh; only then make the final state path unwritable
            // by placing a directory there. No permissions or production files change.
            try FileManager.default.createDirectory(at: failingStore.dataURL,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let failed = !failingForm.submit(to: failingStore)
            checks.append(("failed initial save retains unconfigured state",
                           failed && failingStore.needsInitialSetup && !failingStore.state.initialSetupCompleted))
            checks.append(("failed initial save retains both drafts and displays error",
                           failingForm.left == "Équipe Alpha" && failingForm.right == "Équipe Bêta"
                           && failingForm.saveError != nil))
        } catch {
            checks.append(("initial save failure fixture created", false))
        }

        let saved = form.submit(to: store)
        checks.append(("initial setup saves labels and completion together",
                       saved && store.state.initialSetupCompleted && !store.needsInitialSetup
                       && store.state.globalLabels == form.labels.normalizedForSetup))
        checks.append(("initial setup completes without demonstration projects", store.state.projects.isEmpty))
        checks.append(("setup save precedes floating geometry writes", store.state.windowFrame == nil))
        finishInitialSetup()
        checks.append(("successful setup closes welcome and opens floating panel",
                       welcomeWindow == nil && floating?.isVisible == true))
        let reopened = ProjectStore(directory: store.dataURL.deletingLastPathComponent())
        checks.append(("relaunch keeps labels and skips setup",
                       !reopened.needsInitialSetup && reopened.state.initialSetupCompleted
                       && reopened.state.globalLabels == form.labels.normalizedForSetup))
        let loginStatus = SMAppService.mainApp.status
        login.setEnabled(true)
        checks.append(("test login controller cannot register a system login item",
                       SMAppService.mainApp.status == loginStatus && login.errorMessage != nil))
        return checks
    }

    private func runWindowSmokeTest(initialChecks: [(String, Bool)]) {
        guard let floating else {
            for (name, ok) in initialChecks { print("\(ok ? "PASS" : "FAIL") \(name)") }
            print("FAIL floating panel created after setup")
            fflush(stdout)
            exit(1)
        }
        let p = floating.panel
        var checks: [(String, Bool)] = initialChecks + [
            ("floating level", p.level == .floating),
            ("nonactivating panel", p.styleMask.contains(.nonactivatingPanel)),
            ("does not hide on deactivate", !p.hidesOnDeactivate),
            ("all Spaces", p.collectionBehavior.contains(.canJoinAllSpaces)),
            ("fullscreen auxiliary", p.collectionBehavior.contains(.fullScreenAuxiliary)),
            ("all applications", p.collectionBehavior.contains(.canJoinAllApplications)),
            ("accessory activation policy", NSApp.activationPolicy() == .accessory),
            ("can receive editing keys", p.canBecomeKey),
            ("never a main window", !p.canBecomeMain),
            ("expanded width", p.frame.width == 248),
            ("reference menu icon is a template", statusItem.button?.image?.isTemplate == true),
            ("no opaque titlebar", !p.styleMask.contains(.titled))
        ]
        if let projectID = store.addProject(name: "Projet Alpha"),
           let noteID = store.addNote(projectID: projectID, text: "Note conservée"),
           let original = store.state.projects.first?.notes.first {
            NoteUndo.delete(projectID: projectID, noteID: noteID, store: store, manager: p.undoManager)
            let undo = item("Annuler", action: #selector(undoEdit), key: "z")
            let redo = item("Rétablir", action: #selector(redoEdit), key: "z")
            checks.append(("delete registers note undo", store.state.projects.first?.notes.isEmpty == true))
            checks.append(("undo menu enabled after deletion", validateMenuItem(undo)))
            undoEdit()
            checks.append(("undo handler restores exact note", store.state.projects.first?.notes == [original]))
            checks.append(("redo menu enabled after undo", validateMenuItem(redo)))
            redoEdit()
            checks.append(("redo handler deletes only note", store.state.projects.first?.notes.isEmpty == true
                           && store.state.projects.first?.id == projectID))
        } else {
            checks.append(("note undo fixture", false))
        }
        undoEdit()
        let contentView = p.contentView
        let undoManager = p.undoManager
        let preservedProjects = store.state.projects
        togglePanelMode()
        checks.append(("reduce menu keeps the same panel visible at 148 by 36",
                       floating.mode == .compact && p.isVisible && p.frame.width == 148 && p.frame.height == 36))
        checks.append(("compact panel keeps nonactivating floating and Spaces flags",
                       p.level == .floating && p.styleMask.contains(.nonactivatingPanel)
                       && !p.hidesOnDeactivate && p.collectionBehavior.contains(.canJoinAllSpaces)
                       && p.collectionBehavior.contains(.fullScreenAuxiliary)))
        checks.append(("reduction keeps hosting view and undo session",
                       p.contentView === contentView && p.undoManager === undoManager && !p.isKeyWindow))
        togglePanel()
        checks.append(("hide action completely hides compact panel without changing mode",
                       !floating.isVisible && !store.state.panelVisible && floating.mode == .compact))
        togglePanel()
        checks.append(("show menu restores selected compact mode",
                       floating.isVisible && store.state.panelVisible && floating.mode == .compact
                       && p.frame.width == 148 && p.frame.height == 36))
        var cyclesSucceeded = true
        for _ in 0..<12 {
            cyclesSucceeded = floating.setMode(.expanded) && floating.setMode(.compact) && cyclesSucceeded
        }
        checks.append(("twelve mode cycles preserve projects notes and session",
                       cyclesSucceeded && store.state.projects == preservedProjects
                       && p.contentView === contentView && p.undoManager === undoManager))
        let reloaded = ProjectStore(directory: store.dataURL.deletingLastPathComponent())
        checks.append(("compact mode and both frames survive reloading without setup",
                       reloaded.state.panelMode == .compact && reloaded.state.windowFrame != nil
                       && reloaded.state.compactWindowFrame != nil && !reloaded.needsInitialSetup
                       && reloaded.state.projects == preservedProjects))
        togglePanelMode()
        checks.append(("restore menu returns to expanded content without reloading",
                       floating.mode == .expanded && p.frame.width == 248 && p.isVisible
                       && store.state.projects == preservedProjects && p.contentView === contentView))
        for (name, ok) in checks { print("\(ok ? "PASS" : "FAIL") \(name)") }
        floating.hide()
        let hidden = !floating.isVisible && !store.state.panelVisible
        floating.show()
        let shown = floating.isVisible && store.state.panelVisible
        print("\(hidden && shown ? "PASS" : "FAIL") hide/show with persisted preference")
        p.setFrameOrigin(NSPoint(x: 100_000, y: 100_000))
        floating.resizeToFit()
        let accessible = NSScreen.screens.contains { $0.visibleFrame.contains(p.frame) }
        print("\(accessible ? "PASS" : "FAIL") offscreen frame recovery (simulated)")
        let saved = store.persistenceError == nil && FileManager.default.fileExists(atPath: store.dataURL.path)
        print("\(saved ? "PASS" : "FAIL") sandbox fixture persistence")
        if let directory = smokeDirectory { try? FileManager.default.removeItem(at: directory) }
        fflush(stdout)
        exit(checks.allSatisfy(\.1) && hidden && shown && accessible && saved ? 0 : 1)
    }
#endif
}
