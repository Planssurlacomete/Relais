import Foundation

/// All fixtures are synthetic and use disposable private storage.
enum InitialSetupTests {
    @MainActor static func run(root: URL) throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
            guard try condition() else { throw ModelTests.Failure(description: "FAIL: \(description)") }
            checks += 1
        }
        func folder(_ name: String) throws -> URL {
            let directory = root.appendingPathComponent("setup-" + name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            return directory
        }
        func fixture(_ name: String, data: Data) throws -> URL {
            let directory = try folder(name)
            try data.write(to: directory.appendingPathComponent("state.json"))
            return directory
        }

        let fresh = ProjectStore(directory: try folder("fresh"))
        try check(fresh.needsInitialSetup && !fresh.isDataUnavailable, "Missing state opens initial setup")
        try check(!fresh.state.initialSetupCompleted && fresh.state.projects.isEmpty, "New install has no completed marker or demonstration projects")
        try check(!FileManager.default.fileExists(atPath: fresh.dataURL.path), "Opening setup does not create a state file")
        let initial = fresh.state
        fresh.setWindowFrame(SavedWindowFrame(x: 20, y: 40, width: 248, height: 180))
        fresh.setPanelVisible(false)
        try check(fresh.state == initial && !FileManager.default.fileExists(atPath: fresh.dataURL.path),
                  "Window and visibility callbacks cannot prematurely persist or complete setup")

        let invalid = [
            PositionLabels(left: "", right: ""),
            PositionLabels(left: "Équipe Alpha", right: " \n "),
            PositionLabels(left: " \t ", right: "Équipe Bêta"),
            PositionLabels(left: "Équipe Alpha", right: "éQUIPE alpha"),
            PositionLabels(left: " Équipe  Alpha ", right: "équipe\talpha"),
            PositionLabels(left: "Équipe Café", right: "équipe Cafe\u{301}"),
            PositionLabels(left: String(repeating: "x", count: StateLimits.maximumLabelBytes + 1), right: "Équipe Bêta")
        ]
        for labels in invalid {
            try check(!labels.isValidForInitialSetup, "Invalid initial names disable validation")
            try check(!fresh.completeInitialSetup(labels: labels) && fresh.needsInitialSetup,
                      "Invalid names cannot complete setup")
        }
        try check(!FileManager.default.fileExists(atPath: fresh.dataURL.path), "Invalid validation attempts leave storage absent")
        let entered = PositionLabels(left: "  Équipe\tAlpha 🛰  ", right: " Équipe  Bêta 日本語\n")
        let chosen = PositionLabels(left: "Équipe Alpha 🛰", right: "Équipe Bêta 日本語")
        try check(entered.isValidForInitialSetup && entered.normalizedForSetup == chosen,
                  "Distinct Unicode names are accepted with consistent whitespace normalization")
        try check(fresh.completeInitialSetup(labels: entered), "A valid initial setup saves successfully")
        try check(fresh.state.initialSetupCompleted && !fresh.needsInitialSetup && fresh.state.globalLabels == chosen,
                  "Labels and completion marker become visible together after successful save")
        try check(fresh.state.projects.isEmpty, "Completing setup never seeds demonstration projects")
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: fresh.dataURL)) as! [String: Any]
        try check(persisted["initialSetupCompleted"] as? Bool == true && persisted["schemaVersion"] as? Int == AppState.currentSchemaVersion,
                  "Current schema persists an explicit setup completion marker")
        let emptyReload = ProjectStore(directory: fresh.dataURL.deletingLastPathComponent())
        try check(!emptyReload.needsInitialSetup && emptyReload.state.globalLabels == chosen,
                  "A configured zero-project install skips welcome on relaunch")
        try check(!emptyReload.completeInitialSetup(labels: PositionLabels(left: "Autre côté Alpha", right: "Autre côté Bêta"))
                  && emptyReload.state.globalLabels == chosen, "Setup API cannot overwrite a configured installation")
        let projectID = emptyReload.addProject(name: "Projet Alpha")!
        emptyReload.setPosition(id: projectID, position: .right)
        try check(emptyReload.state.projects[0].position == .right && emptyReload.labels(for: emptyReload.state.projects[0]) == chosen,
                  "The first user-created project uses chosen labels and independent technical positions")
        emptyReload.setCustomLabels(id: projectID, labels: PositionLabels(left: "Étape Alpha", right: "Étape Bêta"))
        try check(emptyReload.state.globalLabels == chosen && emptyReload.state.projects[0].customLabels?.left == "Étape Alpha",
                  "Project customization remains independent of configured global names")
        try check(ProjectStore(directory: fresh.dataURL.deletingLastPathComponent()).state == emptyReload.state,
                  "Names, positions and project customization persist across relaunch")

        for schema in [1, 2] {
            let projectIDs = [UUID(), UUID(), UUID()]
            let pin = RelayNote(text: "Documentation à compléter", isPinned: true, order: 4)
            let ordinary = RelayNote(text: "Tests à effectuer", order: 9)
            let noteData = try JSONEncoder().encode([pin, ordinary])
            let noteObjects = try JSONSerialization.jsonObject(with: noteData)
            var projects: [[String: Any]] = [
                ["id": projectIDs[0].uuidString, "name": "Projet Alpha", "position": "right",
                 "customLabels": ["left": "Étape Alpha", "right": "Étape Bêta"]],
                ["id": projectIDs[1].uuidString, "name": "Projet Bêta", "position": "left"],
                ["id": projectIDs[2].uuidString, "name": "Projet Gamma", "position": "right"]
            ]
            if schema == 2 { projects[0]["notes"] = noteObjects }
            let original: [String: Any] = [
                "schemaVersion": schema, "projects": projects,
                "globalLabels": ["left": "Intervenant Alpha", "right": "Intervenant Bêta"],
                "windowFrame": ["x": 50, "y": 60, "width": 248, "height": 400], "panelVisible": false
            ]
            let data = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
            let legacy = ProjectStore(directory: try fixture("legacy-\(schema)", data: data))
            try check(!legacy.needsInitialSetup && legacy.state.initialSetupCompleted, "Valid legacy state is already configured")
            try check(legacy.state.projects.map(\.id) == projectIDs && legacy.state.projects.map(\.name) == ["Projet Alpha", "Projet Bêta", "Projet Gamma"],
                      "Legacy migration preserves project identities, names and order")
            try check(legacy.state.projects.map(\.position) == [.right, .left, .right]
                      && legacy.state.projects[0].customLabels == PositionLabels(left: "Étape Alpha", right: "Étape Bêta"),
                      "Legacy migration preserves switch positions and custom labels")
            try check(legacy.state.globalLabels == PositionLabels(left: "Intervenant Alpha", right: "Intervenant Bêta")
                      && !legacy.state.panelVisible && legacy.state.windowFrame == SavedWindowFrame(x: 50, y: 60, width: 248, height: 400),
                      "Legacy migration preserves names, visibility and the exact saved frame")
            try check(schema == 1 ? legacy.state.projects.allSatisfy { $0.notes.isEmpty } : legacy.state.projects[0].notes == [pin, ordinary],
                      "Legacy notes, pin metadata, order and identity survive migration")
            try check(try Data(contentsOf: legacy.dataURL) == data, "Reading legacy data alone never rewrites its original bytes")
            let migrated = legacy.state
            legacy.setPanelVisible(true)
            legacy.setPanelVisible(false)
            try check(ProjectStore(directory: legacy.dataURL.deletingLastPathComponent()).state == migrated,
                      "Saving and relaunching a migrated install retains every field")

            let emptyObject: [String: Any] = ["schemaVersion": schema, "projects": [],
                "globalLabels": ["left": "Même nom", "right": "Même nom"], "panelVisible": false]
            let emptyData = try JSONSerialization.data(withJSONObject: emptyObject)
            let emptyLegacy = ProjectStore(directory: try fixture("legacy-empty-\(schema)", data: emptyData))
            try check(!emptyLegacy.needsInitialSetup && emptyLegacy.state.projects.isEmpty
                      && emptyLegacy.state.globalLabels == PositionLabels(left: "Même nom", right: "Même nom"),
                      "An existing empty install skips setup and retains even legacy identical names")
        }

        let failureFolder = try folder("write-failure")
        let failure = ProjectStore(directory: failureFolder)
        let canary = root.appendingPathComponent("setup-canary.txt")
        try Data("Synthetic canary".utf8).write(to: canary)
        try FileManager.default.createSymbolicLink(at: failure.dataURL, withDestinationURL: canary)
        try check(!failure.completeInitialSetup(labels: entered) && failure.needsInitialSetup && !failure.state.initialSetupCompleted,
                  "Write failure never marks setup complete")
        try check(failure.state.globalLabels == .defaults && failure.persistenceError != nil,
                  "Failed setup retains the last saved model and exposes a retryable error")
        try check(try String(contentsOf: canary, encoding: .utf8) == "Synthetic canary", "Failed setup never modifies a symbolic-link target")
        try FileManager.default.removeItem(at: failure.dataURL)
        try check(failure.completeInitialSetup(labels: entered) && failure.state.globalLabels == chosen,
                  "The same entered names can be retried after a transient write failure")
        try check(!ProjectStore(directory: failureFolder).needsInitialSetup, "Retried successful setup survives relaunch")

        for (index, text) in [
            "{invalid json}", "", "{\"schemaVersion\":3,\"projects\":[]}",
            "{\"schemaVersion\":3,\"initialSetupCompleted\":\"yes\",\"projects\":[]}",
            "{\"schemaVersion\":1,\"projects\":\"unreadable\"}",
            "{\"schemaVersion\":99,\"projects\":\"future\"}"
        ].enumerated() {
            let original = Data(text.utf8)
            let blocked = ProjectStore(directory: try fixture("unreadable-\(index)", data: original))
            try check(blocked.isDataUnavailable && !blocked.needsInitialSetup, "Unreadable or future data never opens a fresh welcome flow")
            try check(!blocked.completeInitialSetup(labels: entered) && blocked.addProject(name: "Projet Delta") == nil,
                      "Unreadable or future data rejects setup and project mutations")
            blocked.setWindowFrame(SavedWindowFrame(x: 0, y: 0, width: 248, height: 180))
            blocked.setPanelVisible(false)
            try check(try Data(contentsOf: blocked.dataURL) == original, "Setup, geometry and visibility cannot overwrite an unreadable original")
        }
        return checks
    }
}
