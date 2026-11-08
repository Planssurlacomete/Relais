import Foundation

/// Notes are exercised against disposable private directories, never production data.
enum NoteTests {
    @MainActor
    static func run(root: URL) throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
            guard try condition() else { throw ModelTests.Failure(description: "FAIL: \(description)") }
            checks += 1
        }
        func fixture(_ name: String, _ json: String) throws -> URL {
            let folder = root.appendingPathComponent("notes-\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try Data(json.utf8).write(to: folder.appendingPathComponent("state.json"))
            return folder
        }

        let ids = (0..<3).map { _ in UUID() }
        let legacyJSON = """
        {"schemaVersion":1,"projects":[
        {"id":"\(ids[0])","name":"Projet Alpha","position":"right","customLabels":{"left":"Équipe Alpha personnalisée","right":"Équipe Bêta personnalisée"}},
        {"id":"\(ids[1])","name":"Projet Bêta","position":"left"},
        {"id":"\(ids[2])","name":"Projet Gamma","position":"right"}],
        "globalLabels":{"left":"Équipe Alpha globale","right":"Équipe Bêta globale"},
        "windowFrame":{"x":240,"y":310,"width":248,"height":400},"panelVisible":false}
        """
        let folder = try fixture("migration", legacyJSON)
        let store = ProjectStore(directory: folder)
        let baseline = store.state
        try check(store.state.schemaVersion == AppState.currentSchemaVersion, "1.0.1 migrates to the notes schema")
        try check(store.state.projects.map(\.id) == ids, "Migration preserves all project identities and display order")
        try check(store.state.projects.map(\.position) == [.right, .left, .right], "Migration preserves gauche/droite positions")
        try check(store.state.projects.allSatisfy { $0.notes.isEmpty }, "Existing projects start with zero notes")
        try check(store.state.projects[0].customLabels?.left == "Équipe Alpha personnalisée", "Migration preserves custom labels")
        try check(store.state.globalLabels.left == "Équipe Alpha globale" && !store.state.panelVisible, "Migration preserves global labels and visibility")
        try check(store.state.windowFrame == SavedWindowFrame(x: 240, y: 310, width: 248, height: 400), "Migration preserves the saved window position")
        try check(try String(contentsOf: store.dataURL, encoding: .utf8) == legacyJSON, "Loading alone leaves the original legacy file intact")

        let first = store.addNote(projectID: ids[0], text: "Développement terminé")!
        let second = store.addNote(projectID: ids[0], text: "En attente de validation")!
        let third = store.addNote(projectID: ids[0], text: "Une troisième note")!
        let initial = store.state.projects[0].notes
        try check(initial.count == 3 && Set(initial.map(\.id)).count == 3, "Three independent notes receive unique IDs")
        try check(store.state.projects[0].orderedNotes.map(\.id) == [first, second, third], "Notes retain insertion order")
        try check(store.updateNote(projectID: ids[0], noteID: second, text: "  Documentation à compléter  "), "The second note can be edited")
        let edited = store.state.projects[0].notes
        try check(edited[0] == initial[0] && edited[2] == initial[2], "Editing the second note leaves its siblings unchanged")
        try check(edited[1].id == second && edited[1].order == initial[1].order && !edited[1].isPinned,
                  "Editing preserves the note identity, order and pin state")
        try check(edited[1].text == "Documentation à compléter", "Note edits save the entered text")
        try check(!store.updateNote(projectID: ids[0], noteID: second, text: " \n "), "Blank edits are rejected without deleting the note")
        let removed = store.deleteNote(projectID: ids[0], noteID: first)!
        try check(store.state.projects[0].orderedNotes.map(\.id) == [second, third], "The delete cross removes only its own note")
        try check(store.setNotePinned(projectID: ids[0], noteID: third, isPinned: true), "A note can be pinned")
        try check(store.state.projects[0].orderedNotes.map(\.id) == [third, second], "Pinned notes sort ahead of ordinary notes")
        try check(store.setNotePinned(projectID: ids[0], noteID: third, isPinned: false), "A note can be unpinned")
        try check(store.state.projects[0].orderedNotes.map(\.id) == [second, third], "Unpinning restores the original note order")
        try check(store.restoreNote(projectID: ids[0], note: removed), "Undo can restore a deleted note")
        try check(store.state.projects[0].orderedNotes[0] == removed, "Undo restores the exact text, identity, pin and order")
        try check(!store.restoreNote(projectID: ids[0], note: removed), "Undo cannot duplicate an existing note")
        let elsewhere = store.addNote(projectID: ids[1], text: "En attente de validation")!
        try check(store.state.projects[1].notes.map(\.id) == [elsewhere], "Another project has its own independent collection")
        try check(store.state.projects[2] == baseline.projects[2], "A project without edited notes stays byte-for-byte equivalent")
        store.setNotePinned(projectID: ids[0], noteID: first, isPinned: true)
        store.setNotePinned(projectID: ids[0], noteID: third, isPinned: true)
        try check(store.state.projects[0].orderedNotes.map(\.id) == [first, third, second], "Multiple pinned notes preserve their relative order")
        store.setNotePinned(projectID: ids[0], noteID: first, isPinned: false)
        let fullState = store.state
        let reloaded = ProjectStore(directory: folder)
        try check(reloaded.state == fullState && reloaded.persistenceError == nil, "All notes and their order persist after relaunch")
        try check(reloaded.state.projects[0].orderedNotes[0].id == third && reloaded.state.projects[0].orderedNotes[0].isPinned,
                  "Pinning survives relaunch while ordinary notes are also retained")
        var projectsWithoutNotes = reloaded.state.projects
        for index in projectsWithoutNotes.indices { projectsWithoutNotes[index].notes = [] }
        try check(projectsWithoutNotes == baseline.projects, "Note actions leave every project name, ID, position, label and project order intact")
        try check(reloaded.state.windowFrame == baseline.windowFrame && reloaded.state.globalLabels == baseline.globalLabels
                  && reloaded.state.panelVisible == baseline.panelVisible, "Note actions leave preferences and the saved frame intact")
        for note in reloaded.state.projects[0].notes { reloaded.deleteNote(projectID: ids[0], noteID: note.id) }
        try check(reloaded.state.projects[0].notes.isEmpty, "Every note may be removed without removing the project")
        try check(ProjectStore(directory: folder).state.projects[0].notes.isEmpty, "Zero notes persist after relaunch")
        try check(reloaded.addNote(projectID: UUID(), text: "Orpheline") == nil, "Adding a note cannot create an unknown project")
        try check(reloaded.deleteNote(projectID: ids[1], noteID: UUID()) == nil, "Deleting an unknown note is harmless")
        try check(!reloaded.updateNote(projectID: ids[0], noteID: elsewhere, text: "Pas ici"), "Notes cannot be edited through another project")
        try check(!reloaded.setNotePinned(projectID: ids[0], noteID: elsewhere, isPinned: true), "Notes cannot be pinned through another project")

        let singleID = UUID()
        let singleDir = try fixture("single", """
        {"projects":[{"id":"\(singleID)","name":"Prototype","position":"right","note":"Ne pas perdre ce texte","notePinned":true}]}
        """)
        let single = ProjectStore(directory: singleDir)
        try check(single.state.projects[0].notes.count == 1 && single.state.projects[0].notes[0].text == "Ne pas perdre ce texte",
                  "An intermediate single string note migrates without content loss")
        try check(single.state.projects[0].notes[0].isPinned && single.state.projects[0].position == .right,
                  "Single-note migration preserves the pin and switch position")
        let objectNote = RelayNote(text: "Objet ancien", isPinned: true, order: 7)
        let objectJSON = String(decoding: try JSONEncoder().encode(objectNote), as: UTF8.self)
        let objectDir = try fixture("single-object", """
        {"projects":[{"name":"Prototype objet","note":\(objectJSON)}]}
        """)
        let objectStore = ProjectStore(directory: objectDir)
        try check(objectStore.state.projects[0].notes == [objectNote], "An intermediate note object retains all metadata")

        let corruptJSON = """
        {"schemaVersion":2,"projects":[
        {"id":"\(ids[0])","name":"Projet Alpha","position":"right","notes":[
          {"id":"\(first)","text":"Valide","isPinned":true,"order":10},
          {"id":"invalide","text":"Texte récupérable","isPinned":"wrong","order":"wrong"},
          {"text":42},null,
          {"id":"\(first)","text":"Doublon à conserver","order":12}]},
        {"id":"\(ids[1])","name":"Projet Bêta","position":"left","notes":{"wrong":"shape"}},
        {"id":"\(ids[2])","name":"Projet Gamma","position":"right"}],
        "globalLabels":{"left":"Équipe Alpha","right":"Équipe Bêta"},"panelVisible":false}
        """
        let corruptDir = try fixture("damaged", corruptJSON)
        let recovered = ProjectStore(directory: corruptDir)
        try check(recovered.state.projects.map(\.id) == ids, "Malformed notes never discard any project")
        try check(recovered.state.projects.map(\.position) == [.right, .left, .right], "Malformed notes leave switch positions intact")
        try check(recovered.state.projects[0].notes.map(\.text) == ["Valide", "Texte récupérable", "Doublon à conserver"],
                  "Valid text is recovered despite invalid metadata and malformed sibling notes")
        try check(Set(recovered.state.projects[0].notes.map(\.id)).count == 3, "Duplicate note IDs are repaired without losing text")
        try check(recovered.state.projects[1].notes.isEmpty && recovered.persistenceError != nil, "A malformed collection is isolated and explained")
        try check(try String(contentsOf: recovered.dataURL, encoding: .utf8) == corruptJSON, "Recovery leaves the source file unchanged until an explicit mutation")
        let recoveries = try FileManager.default.contentsOfDirectory(at: corruptDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("state.notes-recovery-") }
        try check(recoveries.count == 1 && (try String(contentsOf: recoveries[0], encoding: .utf8)) == corruptJSON,
                  "All malformed note payloads survive in an exact private recovery backup")
        let permissions = try FileManager.default.attributesOfItem(atPath: recoveries[0].path)[.posixPermissions] as? NSNumber
        try check(permissions?.intValue == 0o600, "Note recovery backups are private (0600)")
        try check(recovered.addNote(projectID: ids[1], text: "Après récupération") != nil, "Recovered projects remain editable after the source was safely backed up")
        try check(ProjectStore(directory: corruptDir).state == recovered.state, "Recovered projects and notes persist intact after saving")

        let manyNotes = (0..<1_000).map { RelayNote(text: "Note \($0)", order: $0) }
        let manyState = AppState(projects: [RelayProject(id: ids[0], name: "Nombreuses notes", notes: manyNotes)])
        let manyJSON = String(decoding: try JSONEncoder().encode(manyState), as: UTF8.self)
        let many = ProjectStore(directory: try fixture("many", manyJSON))
        try check(many.state.projects[0].notes.count == 1_000, "A collection of 1,000 notes loads without a per-project count limit")
        try check(many.addNote(projectID: ids[0], text: "Encore une") != nil && many.state.projects[0].notes.count == 1_001,
                  "A large collection can still accept another note")

        let highest = RelayNote(text: "Ordre maximal", order: Int.max)
        let extremeState = AppState(projects: [RelayProject(id: ids[0], name: "Ordre extrême", notes: [highest])])
        let extremeJSON = String(decoding: try JSONEncoder().encode(extremeState), as: UTF8.self)
        let extreme = ProjectStore(directory: try fixture("extreme-order", extremeJSON))
        let appended = extreme.addNote(projectID: ids[0], text: "Ajout sans débordement")
        try check(appended != nil && extreme.state.projects[0].notes[0] == highest,
                  "Int.max order cannot overflow or modify an existing note when appending")
        try check(extreme.state.projects[0].orderedNotes.map(\.id) == [highest.id, appended!],
                  "Stable ordering still appends after a note whose order is Int.max")

        let failed = ProjectStore(directory: try fixture("failed-write", legacyJSON))
        let failedNoteID = failed.addNote(projectID: ids[0], text: "Conservée")!
        let saved = failed.state
        let target = root.appendingPathComponent("notes-protected-target")
        try Data("ne pas modifier".utf8).write(to: target)
        try FileManager.default.removeItem(at: failed.dataURL)
        try FileManager.default.createSymbolicLink(at: failed.dataURL, withDestinationURL: target)
        try check(!failed.updateNote(projectID: ids[0], noteID: failedNoteID, text: "Échec"), "A note edit reports persistence failure")
        try check(failed.deleteNote(projectID: ids[0], noteID: failedNoteID) == nil, "A failed note deletion is not published")
        try check(failed.addNote(projectID: ids[0], text: "Échec") == nil && failed.state == saved, "Failed note mutations retain the entire saved state")
        try check(try String(contentsOf: target, encoding: .utf8) == "ne pas modifier", "Failed notes writes never follow a symbolic-link target")
        return checks
    }
}
