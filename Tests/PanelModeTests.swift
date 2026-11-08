import Foundation

/// Mode persistence and migration use synthetic data in disposable private stores.
enum PanelModeTests {
    @MainActor static func run(root: URL) throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
            guard try condition() else { throw ModelTests.Failure(description: "FAIL: \(description)") }
            checks += 1
        }
        func folder(_ name: String) throws -> URL {
            let path = root.appendingPathComponent("panel-mode-" + name, isDirectory: true)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            return path
        }
        func fixture(_ name: String, object: [String: Any]) throws -> (ProjectStore, Data) {
            let directory = try folder(name)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent("state.json"))
            return (ProjectStore(directory: directory), data)
        }
        func object(_ state: AppState) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        }

        let expanded = SavedWindowFrame(x: 120, y: 240, width: 248, height: 400)
        let compact = SavedWindowFrame(x: 150, y: 580, width: 144, height: 36)
        let movedExpanded = SavedWindowFrame(x: 220, y: 140, width: 248, height: 480)
        let movedCompact = SavedWindowFrame(x: 310, y: 510, width: 144, height: 36)
        let labels = PositionLabels(left: "Équipe Alpha", right: "Équipe Bêta")
        let store = ProjectStore(directory: try folder("fresh"))
        let freshState = store.state
        try check(store.state.panelMode == .expanded && store.state.compactWindowFrame == nil,
                  "New state defaults to expanded mode without a compact frame")
        try check(!store.setPanelMode(.compact), "Mode changes cannot complete initial setup")
        store.setWindowFrame(compact, mode: .compact)
        store.setWindowFrame(expanded, mode: .expanded)
        store.setWindowFrame(compact)
        store.setPanelVisible(false)
        try check(store.state == freshState && !FileManager.default.fileExists(atPath: store.dataURL.path),
                  "Mode, frame and visibility callbacks cannot create storage before setup")
        try check(store.completeInitialSetup(labels: labels), "Synthetic mode fixture completes its own initial setup")
        let alpha = store.addProject(name: "Projet Alpha")!
        let beta = store.addProject(name: "Projet Bêta")!
        let gamma = store.addProject(name: "Projet Gamma")!
        store.setPosition(id: alpha, position: .right)
        store.setCustomLabels(id: beta, labels: PositionLabels(left: "Étape Alpha", right: "Étape Bêta"))
        let pinned = store.addNote(projectID: alpha, text: "Documentation à compléter")!
        store.setNotePinned(projectID: alpha, noteID: pinned, isPinned: true)
        _ = store.addNote(projectID: alpha, text: "Tests à effectuer")
        _ = store.addNote(projectID: gamma, text: "En attente de validation")
        store.moveProject(id: gamma, before: alpha)
        let core = store.state
        store.setWindowFrame(expanded)
        try check(store.state.windowFrame == expanded && store.state.compactWindowFrame == nil,
                  "Default frame writes target the active expanded mode")
        try check(store.setPanelMode(.compact) && store.state.panelVisible,
                  "Reducing persists the compact mode without hiding the panel")
        store.setWindowFrame(compact)
        try check(store.state.windowFrame == expanded && store.state.compactWindowFrame == compact,
                  "The compact frame is stored independently of the expanded frame")
        store.setWindowFrame(movedExpanded, mode: .expanded)
        try check(store.state.panelMode == .compact && store.state.windowFrame == movedExpanded
                  && store.state.compactWindowFrame == compact,
                  "An explicit inactive-mode frame write changes neither active mode nor its frame")
        store.setWindowFrame(movedCompact, mode: .compact)
        let compactReload = ProjectStore(directory: store.dataURL.deletingLastPathComponent())
        try check(compactReload.state == store.state && compactReload.state.panelMode == .compact,
                  "A visible compact panel and both mode frames persist after relaunch")
        try check(!compactReload.needsInitialSetup && compactReload.state.initialSetupCompleted,
                  "Restoring compact mode never requests configuration again")
        for _ in 0..<6 {
            try check(store.setPanelMode(.expanded) && store.state.windowFrame == movedExpanded,
                      "Restoring expanded mode retains its last independent frame")
            try check(store.setPanelMode(.compact) && store.state.compactWindowFrame == movedCompact,
                      "Reducing again retains the compact frame")
        }
        try check(store.state.projects == core.projects && store.state.globalLabels == core.globalLabels
                  && store.state.initialSetupCompleted == core.initialSetupCompleted,
                  "Repeated mode cycles preserve all project, note, label and setup state")
        store.setPanelVisible(false)
        let hiddenReload = ProjectStore(directory: store.dataURL.deletingLastPathComponent())
        try check(!hiddenReload.state.panelVisible && hiddenReload.state.panelMode == .compact,
                  "Complete hiding is independent of the remembered compact mode")
        hiddenReload.setPanelVisible(true)
        try check(hiddenReload.state.panelMode == .compact && hiddenReload.state.projects == core.projects,
                  "Showing a hidden panel preserves mode and every project")
        hiddenReload.setPanelVisible(false)
        try check(hiddenReload.setPanelMode(.expanded) && !hiddenReload.state.panelVisible,
                  "Changing a remembered mode does not implicitly show a hidden panel")
        let hiddenExpanded = ProjectStore(directory: hiddenReload.dataURL.deletingLastPathComponent())
        try check(hiddenExpanded.state.panelMode == .expanded && !hiddenExpanded.state.panelVisible
                  && hiddenExpanded.state.windowFrame == movedExpanded && hiddenExpanded.state.compactWindowFrame == movedCompact,
                  "Hidden expanded mode and both independent positions survive relaunch")
        let unchanged = hiddenExpanded.state
        hiddenExpanded.setWindowFrame(SavedWindowFrame(x: .nan, y: 0, width: 144, height: 36), mode: .compact)
        hiddenExpanded.setWindowFrame(SavedWindowFrame(x: 0, y: 0, width: 0, height: 36), mode: .compact)
        hiddenExpanded.setWindowFrame(SavedWindowFrame(x: 0, y: 0, width: 248, height: -1), mode: .expanded)
        try check(hiddenExpanded.state == unchanged, "Invalid frames cannot replace either mode position")
        let noOpBytes = try Data(contentsOf: hiddenExpanded.dataURL) + Data("\n\n".utf8)
        try noOpBytes.write(to: hiddenExpanded.dataURL)
        try check(hiddenExpanded.setPanelMode(.expanded), "An already-selected mode succeeds as a no-op")
        hiddenExpanded.setWindowFrame(movedExpanded)
        try check(try Data(contentsOf: hiddenExpanded.dataURL) == noOpBytes, "No-op mode and frame updates do not rewrite the state file")

        for schema in [1, 2, 3] {
            var legacy = core
            legacy.windowFrame = expanded
            legacy.panelVisible = false
            if schema == 1 {
                for index in legacy.projects.indices { legacy.projects[index].notes = [] }
            }
            var source = try object(legacy)
            source["schemaVersion"] = schema
            source.removeValue(forKey: "panelMode")
            source.removeValue(forKey: "compactWindowFrame")
            if schema < 3 { source.removeValue(forKey: "initialSetupCompleted") }
            let (migrated, original) = try fixture("schema-\(schema)", object: source)
            try check(migrated.state.schemaVersion == AppState.currentSchemaVersion
                      && migrated.state.panelMode == .expanded && migrated.state.compactWindowFrame == nil,
                      "Legacy schema \(schema) gains compatible expanded mode defaults")
            try check(!migrated.needsInitialSetup && migrated.state.initialSetupCompleted,
                      "Legacy schema \(schema) remains configured")
            try check(migrated.state.projects == legacy.projects && migrated.state.globalLabels == legacy.globalLabels
                      && migrated.state.windowFrame == expanded && !migrated.state.panelVisible,
                      "Legacy schema \(schema) preserves projects, notes, labels, order, frame and visibility")
            try check(try Data(contentsOf: migrated.dataURL) == original, "Loading legacy mode defaults never rewrites original bytes")
            try check(migrated.setPanelMode(.compact), "Migrated schema \(schema) accepts the new compact preference")
            let reload = ProjectStore(directory: migrated.dataURL.deletingLastPathComponent())
            try check(reload.state == migrated.state && reload.state.projects == legacy.projects && !reload.needsInitialSetup,
                      "Saving and reloading migrated schema \(schema) retains all user fields")

            source["projects"] = []
            let (emptyLegacy, _) = try fixture("empty-schema-\(schema)", object: source)
            try check(!emptyLegacy.needsInitialSetup && emptyLegacy.state.projects.isEmpty
                      && emptyLegacy.state.globalLabels == legacy.globalLabels && emptyLegacy.state.panelMode == .expanded,
                      "An existing empty schema \(schema) install migrates without new setup")
        }

        var valid = core
        valid.windowFrame = expanded
        valid.panelMode = .compact
        valid.compactWindowFrame = compact
        let validObject = try object(valid)
        let invalidPreferences: [[String: Any]] = [
            ["panelMode": "unknown-mode"],
            ["panelMode": 42, "compactWindowFrame": "wrong-shape"],
            ["panelMode": NSNull(), "compactWindowFrame": ["x": 0, "y": 0, "width": -1, "height": 36]],
            ["compactWindowFrame": ["x": "wrong-type", "y": 0, "width": 144, "height": 36]],
            ["windowFrame": ["unexpected": true]]
        ]
        for (index, changes) in invalidPreferences.enumerated() {
            var source = validObject
            for (key, value) in changes { source[key] = value }
            let (recovered, original) = try fixture("invalid-preferences-\(index)", object: source)
            try check(!recovered.isDataUnavailable && !recovered.needsInitialSetup && recovered.state.projects == core.projects
                      && recovered.state.globalLabels == core.globalLabels,
                      "Malformed mode preferences are isolated from every project and initial setup")
            if changes["panelMode"] != nil {
                try check(recovered.state.panelMode == .expanded, "Unknown or wrongly typed mode falls back to expanded")
            }
            if changes["compactWindowFrame"] != nil {
                try check(recovered.state.compactWindowFrame == nil, "An invalid compact frame falls back without deleting project data")
            }
            try check(try Data(contentsOf: recovered.dataURL) == original, "Recovering window preferences leaves the source unchanged")
            let backups = try FileManager.default.contentsOfDirectory(at: recovered.dataURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("state.preferences-recovery-") }
            try check(backups.count == 1 && (try Data(contentsOf: backups[0])) == original,
                      "Malformed window preferences receive an exact original-file backup before any mutation")
            let permissions = try FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as? NSNumber
            try check(permissions?.intValue == 0o600 && recovered.persistenceError != nil,
                      "Window preference recovery is explained and its backup remains private")
            try check(recovered.setPanelMode(recovered.state.panelMode == .expanded ? .compact : .expanded),
                      "Recovered state remains writable after the original has been safely backed up")
            let reload = ProjectStore(directory: recovered.dataURL.deletingLastPathComponent())
            try check(reload.state == recovered.state && reload.state.projects == core.projects,
                      "Saving recovered preferences preserves all projects and notes on relaunch")
        }

        let (failed, _) = try fixture("write-failure", object: try object(core))
        let beforeFailure = failed.state
        let canary = root.appendingPathComponent("panel-mode-canary.txt")
        try Data("Synthetic canary".utf8).write(to: canary)
        try FileManager.default.removeItem(at: failed.dataURL)
        try FileManager.default.createSymbolicLink(at: failed.dataURL, withDestinationURL: canary)
        try check(!failed.setPanelMode(.compact) && failed.state == beforeFailure && failed.persistenceError != nil,
                  "A failed compact-mode write preserves the full saved state and reports failure")
        failed.setWindowFrame(compact, mode: .compact)
        failed.setWindowFrame(expanded, mode: .expanded)
        failed.setPanelVisible(false)
        try check(failed.state == beforeFailure && (try String(contentsOf: canary, encoding: .utf8)) == "Synthetic canary",
                  "Failed frame and visibility writes never alter projects or a symbolic-link target")
        try FileManager.default.removeItem(at: failed.dataURL)
        try check(failed.setPanelMode(.compact) && !ProjectStore(directory: failed.dataURL.deletingLastPathComponent()).needsInitialSetup,
                  "A transient mode-write failure can be retried without reconfiguration")

        for (index, source) in [
            ["schemaVersion": 3, "projects": []] as [String: Any],
            ["schemaVersion": 4, "projects": [], "panelMode": "compact"] as [String: Any],
            ["schemaVersion": 99, "projects": "future"] as [String: Any]
        ].enumerated() {
            let (blocked, original) = try fixture("unavailable-\(index)", object: source)
            try check(blocked.isDataUnavailable && !blocked.needsInitialSetup && !blocked.setPanelMode(.compact),
                      "A missing required setup marker or future schema blocks mode writes without new setup")
            blocked.setWindowFrame(compact, mode: .compact)
            blocked.setWindowFrame(expanded, mode: .expanded)
            blocked.setPanelVisible(false)
            try check(try Data(contentsOf: blocked.dataURL) == original,
                      "Mode, frames and visibility leave unavailable data byte-for-byte unchanged")
        }
        return checks
    }
}
