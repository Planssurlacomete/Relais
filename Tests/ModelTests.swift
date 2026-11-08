import Foundation
import Darwin

/// Dependency-free behavioral tests. Never touches the user's Application Support directory.
@main
struct ModelTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Relais-Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
            guard try condition() else { throw Failure(description: "FAIL: \(description)") }
            checks += 1
        }
        func directory(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
        func writeFixture(_ name: String, _ json: String) throws -> URL {
            let folder = directory(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: folder.appendingPathComponent("state.json"))
            return folder
        }

        let store = ProjectStore(directory: directory("normal"))
        try check(store.state.projects.isEmpty, "First launch is empty")
        try check(store.state.globalLabels == .defaults, "Unconfigured state uses a neutral internal fallback")
        try check(store.state.panelVisible, "Unconfigured state retains a panel visibility preference")
        try check(store.completeInitialSetup(labels: PositionLabels(left: "Équipe Alpha", right: "Équipe Bêta")), "Normal tests start with a completed setup")
        try check(store.addProject(name: " \n ") == nil, "Blank project is rejected")
        let a = store.addProject(name: "Projet Alpha")!
        let b = store.addProject(name: "Projet Bêta")!
        let c = store.addProject(name: "Projet Gamma 🎨 日本語")!
        try check(store.state.projects.count == 3, "Three projects created")
        try check(Set(store.state.projects.map(\.id)).count == 3, "Unique IDs")
        try check(store.state.projects.allSatisfy { $0.position == .left }, "New projects start left")
        try check(store.state.projects.allSatisfy { $0.customLabels == nil }, "New projects inherit dynamically")
        store.setPosition(id: b, position: .right)
        try check(store.state.projects.map(\.position) == [.left, .right, .left], "Switches are independent")
        let initialPositions = store.state.projects.map(\.position)
        let global = PositionLabels(left: "Analyse 🔎", right: "Développement")
        store.setGlobalLabels(global)
        try check(store.state.projects.allSatisfy { store.labels(for: $0) == global }, "Global label propagation")
        try check(store.state.projects.map(\.position) == initialPositions, "Renaming labels preserves positions")
        let custom = PositionLabels(left: "Équipe Alpha", right: "Équipe Bêta")
        store.setCustomLabels(id: c, labels: custom)
        try check(store.labels(for: store.state.projects[2]) == custom, "Per-project labels")
        try check(store.labels(for: store.state.projects[0]) == global, "Customization leaves siblings unchanged")
        let nextGlobal = PositionLabels(left: "Équipe Alpha", right: "Équipe Bêta")
        store.setGlobalLabels(nextGlobal)
        try check(store.labels(for: store.state.projects[0]) == nextGlobal, "Inherited labels track later global edits")
        try check(store.labels(for: store.state.projects[2]) == custom, "Custom labels survive later global edits")
        store.setCustomLabels(id: c, labels: nil)
        try check(store.state.projects[2].customLabels == nil, "Reset restores inheritance")
        try check(store.labels(for: store.state.projects[2]) == nextGlobal, "Reset resolves current global labels")
        store.setGlobalLabels(PositionLabels(left: " ", right: "x"))
        try check(store.state.globalLabels == nextGlobal, "Blank global label is rejected")
        store.setCustomLabels(id: a, labels: PositionLabels(left: "x", right: "\n"))
        try check(store.state.projects[0].customLabels == nil, "Blank custom label is rejected")
        store.setCustomLabels(id: a, labels: PositionLabels(left: "  Équipe Alpha  ", right: "Équipe Bêta \n"))
        try check(store.state.projects[0].customLabels == PositionLabels(left: "Équipe Alpha", right: "Équipe Bêta"), "Custom labels trimmed")
        store.renameProject(id: a, name: " \nUn très long nom de projet — café ☕️  ")
        try check(store.state.projects[0].name == "Un très long nom de projet — café ☕️", "Rename preserves Unicode and trims whitespace")
        store.renameProject(id: a, name: " ")
        try check(store.state.projects[0].name.contains("café"), "Blank rename rejected")
        store.moveProject(id: c, before: a)
        try check(store.state.projects.map(\.id) == [c, a, b], "Drag reorder before first row")
        store.moveProject(id: c, before: nil)
        try check(store.state.projects.map(\.id) == [a, b, c], "Drag reorder to end")
        store.moveProject(id: a, before: c)
        try check(store.state.projects.map(\.id) == [b, a, c], "Forward reorder adjusts indices")
        let order = store.state.projects.map(\.id)
        store.moveProject(id: a, before: a)
        store.moveProject(id: a, before: UUID())
        store.moveProject(id: UUID(), before: a)
        try check(store.state.projects.map(\.id) == order, "Invalid drops leave order intact")
        let frame = SavedWindowFrame(x: 240, y: 310, width: 248, height: 400)
        store.setWindowFrame(frame)
        store.setPanelVisible(false)
        let reloaded = ProjectStore(directory: directory("normal"))
        try check(reloaded.state == store.state, "Relaunch preserves full state: names, positions, custom labels, order, frame, visibility")
        try check(reloaded.persistenceError == nil, "Successful reload has no error")
        reloaded.setWindowFrame(SavedWindowFrame(x: .nan, y: 0, width: 248, height: 400))
        reloaded.setWindowFrame(SavedWindowFrame(x: 0, y: 0, width: 0, height: 400))
        try check(reloaded.state.windowFrame == frame, "Invalid frames rejected")
        reloaded.deleteProject(id: a)
        try check(reloaded.state.projects.map(\.id) == [b, c], "Deletion preserves other IDs and order")
        reloaded.deleteProject(id: UUID())
        try check(reloaded.state.projects.count == 2, "Unknown deletion does nothing")
        reloaded.deleteProject(id: b)
        reloaded.deleteProject(id: c)
        try check(ProjectStore(directory: directory("normal")).state.projects.isEmpty, "Empty list survives relaunch")

        // A no-op must not rewrite disk: preserve insignificant fixture whitespace as evidence.
        let noOpData = try Data(contentsOf: reloaded.dataURL) + Data("\n\n".utf8)
        try noOpData.write(to: reloaded.dataURL)
        reloaded.setGlobalLabels(reloaded.state.globalLabels)
        reloaded.setPanelVisible(reloaded.state.panelVisible)
        try check(try Data(contentsOf: reloaded.dataURL) == noOpData, "No-op mutations do not rewrite disk")

        let legacyID = UUID()
        let legacyDir = try writeFixture("legacy", """
        {"projects":[{"id":"\(legacyID.uuidString)","name":"Ancien projet"}]}
        """)
        let legacy = ProjectStore(directory: legacyDir)
        try check(legacy.state.projects.first?.id == legacyID, "Legacy schema retains identity")
        try check(legacy.state.projects.first?.position == .left, "Missing legacy position defaults left")
        try check(legacy.state.globalLabels == .defaults && legacy.state.panelVisible, "Missing legacy settings have defaults")
        legacy.setPosition(id: legacyID, position: .right)
        try check(ProjectStore(directory: legacyDir).state.projects.first?.position == .right, "Legacy state can be saved in current schema")

        let normalizeID = UUID()
        let normalizeDir = try writeFixture("normalization", """
        {"schemaVersion":1,"globalLabels":{"left":" ","right":"B"},
         "projects":[
           {"id":"\(normalizeID.uuidString)","name":"  Conservé  ","position":"unknown","customLabels":{"left":" ","right":"B"}},
           {"id":"\(normalizeID.uuidString)","name":"Doublon","position":"right"},
           {"name":"   ","position":"left"}],
         "windowFrame":{"x":0,"y":0,"width":-5,"height":30}}
        """)
        let normalized = ProjectStore(directory: normalizeDir)
        try check(normalized.state.projects.count == 1, "Duplicate IDs and blank names normalized")
        try check(normalized.state.projects[0].name == "Conservé", "Valid project remains readable")
        try check(normalized.state.projects[0].position == .left, "Unknown binary position recovers left")
        try check(normalized.state.projects[0].customLabels == nil, "Blank saved customization recovers inheritance")
        try check(normalized.state.globalLabels == .defaults, "Blank saved global labels recover defaults")
        try check(normalized.state.windowFrame == nil, "Invalid saved frame discarded")

        let brokenJSON = "{ this is not JSON }"
        let brokenDir = try writeFixture("corrupt", brokenJSON)
        let broken = ProjectStore(directory: brokenDir)
        try check(broken.state.projects.isEmpty && broken.persistenceError != nil, "Corrupt JSON reports recovery without crashing")
        let backups = try FileManager.default.contentsOfDirectory(at: brokenDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("state.invalid-") }
        try check(backups.count == 1, "Exactly one recovery backup created")
        try check(try String(contentsOf: backups[0], encoding: .utf8) == brokenJSON, "Backup preserves exact corrupt file")
        try check(broken.addProject(name: "Projet Alpha") == nil && broken.isDataUnavailable && !broken.needsInitialSetup, "Unreadable data blocks writes and never opens fresh setup")
        try check(broken.persistenceError != nil, "Unreadable-data warning remains until the original is repaired")
        try check(try String(contentsOf: broken.dataURL, encoding: .utf8) == brokenJSON, "Unreadable original remains byte-for-byte intact after refused writes")

        // Even an undecodable future format must never be backed up and overwritten as corruption.
        let futureJSON = "{\"schemaVersion\":99,\"projects\":\"a new incompatible format\"}"
        let futureDir = try writeFixture("future", futureJSON)
        let future = ProjectStore(directory: futureDir)
        try check(future.persistenceError != nil, "Future schema reports incompatible version")
        try check(future.addProject(name: "Ne pas écraser") == nil, "Future schema rejects writes")
        future.setPanelVisible(false)
        future.setGlobalLabels(PositionLabels(left: "A", right: "B"))
        try check(try String(contentsOf: future.dataURL, encoding: .utf8) == futureJSON, "Future schema original remains byte-for-byte intact")

        let blockedDirectory = root.appendingPathComponent("a-file-not-directory")
        try Data("do not replace".utf8).write(to: blockedDirectory)
        let blocked = ProjectStore(directory: blockedDirectory)
        try check(blocked.addProject(name: "Impossible") == nil, "Write failure is returned to caller")
        try check(blocked.state.projects.isEmpty, "Failed save does not publish unsaved project")
        try check(blocked.persistenceError != nil, "Write failure exposed for UI")
        try check(try String(contentsOf: blockedDirectory, encoding: .utf8) == "do not replace", "Write failure leaves existing file intact")

        let limits = ProjectStore(directory: directory("limits"))
        let boundaryName = String(repeating: "🟢", count: StateLimits.maximumProjectNameBytes / 4)
        let boundaryID = limits.addProject(name: boundaryName)!
        try check(limits.state.projects[0].name == boundaryName, "UTF-8 project-name boundary is accepted")
        let beforeOversizedEdit = limits.state
        try check(limits.addProject(name: boundaryName + "x") == nil, "Oversized project creation is rejected")
        try check(limits.persistenceError != nil, "Oversized creation explains the limit")
        limits.renameProject(id: boundaryID, name: boundaryName + "x")
        try check(limits.state == beforeOversizedEdit && limits.persistenceError != nil, "Oversized rename preserves saved name and reports error")
        let boundaryLabel = String(repeating: "x", count: StateLimits.maximumLabelBytes)
        limits.setGlobalLabels(PositionLabels(left: boundaryLabel, right: "B"))
        try check(limits.state.globalLabels.left == boundaryLabel, "Label byte boundary accepted")
        limits.setGlobalLabels(PositionLabels(left: boundaryLabel + "x", right: "B"))
        try check(limits.state.globalLabels.left == boundaryLabel && limits.persistenceError != nil, "Oversized global label rejected visibly")
        limits.setCustomLabels(id: boundaryID, labels: PositionLabels(left: "A", right: String(repeating: "🟢", count: StateLimits.maximumLabelBytes / 4 + 1)))
        try check(limits.state.projects[0].customLabels == nil && limits.persistenceError != nil, "Multibyte custom-label limit enforced")
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: limits.dataURL.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        let filePermissions = try FileManager.default.attributesOfItem(atPath: limits.dataURL.path)[.posixPermissions] as? NSNumber
        try check(directoryPermissions?.intValue == 0o700, "Data directory is private (0700)")
        try check(filePermissions?.intValue == 0o600, "Atomic state file is private (0600)")
        let backupPermissions = try FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as? NSNumber
        try check(backupPermissions?.intValue == 0o600, "Recovery backup is private (0600)")

        let fullProjects = (0..<StateLimits.maximumProjects).map { RelayProject(name: "Projet \($0)") }
        let fullJSON = try JSONEncoder().encode(AppState(projects: fullProjects))
        let fullDir = try writeFixture("project-boundary", String(decoding: fullJSON, as: UTF8.self))
        let full = ProjectStore(directory: fullDir)
        try check(full.state.projects.count == StateLimits.maximumProjects, "Project-count boundary loads intact")
        try check(full.addProject(name: "Un de trop") == nil && full.persistenceError != nil, "Project-count edit limit is visible")
        try check(try Data(contentsOf: full.dataURL) == fullJSON, "Rejected project leaves original bytes intact")
        full.deleteProject(id: fullProjects[0].id)
        try check(full.addProject(name: "Une place libérée") != nil, "Deleting a project releases capacity")

        // Unsafe or oversized input is preserved read-only, never normalized into an empty saved file.
        let tooManyJSON = try JSONEncoder().encode(AppState(projects: fullProjects + [RelayProject(name: "Excédent")]))
        let tooManyDir = try writeFixture("too-many", String(decoding: tooManyJSON, as: UTF8.self))
        let tooMany = ProjectStore(directory: tooManyDir)
        try check(tooMany.persistenceError != nil && tooMany.addProject(name: "Refusé") == nil, "Oversized project array locks writes")
        try check(try Data(contentsOf: tooMany.dataURL) == tooManyJSON, "Oversized project array preserved byte-for-byte")
        let longNameJSON = try JSONEncoder().encode(AppState(projects: [RelayProject(name: boundaryName + "x")]))
        let longNameDir = try writeFixture("long-saved-name", String(decoding: longNameJSON, as: UTF8.self))
        let longNameStore = ProjectStore(directory: longNameDir)
        try check(longNameStore.addProject(name: "Refusé") == nil && longNameStore.persistenceError != nil, "Oversized decoded project name locks writes")
        try check(try Data(contentsOf: longNameStore.dataURL) == longNameJSON, "Oversized decoded name is not truncated or overwritten")
        let longLabelJSON = try JSONEncoder().encode(AppState(globalLabels: PositionLabels(left: boundaryLabel + "x", right: "B")))
        let longLabelDir = try writeFixture("long-saved-label", String(decoding: longLabelJSON, as: UTF8.self))
        let longLabelStore = ProjectStore(directory: longLabelDir)
        try check(longLabelStore.persistenceError != nil && longLabelStore.addProject(name: "Refusé") == nil, "Oversized decoded label locks writes")
        try check(try Data(contentsOf: longLabelStore.dataURL) == longLabelJSON, "Oversized decoded label preserved")
        let hugeDir = directory("huge-file")
        try FileManager.default.createDirectory(at: hugeDir, withIntermediateDirectories: true)
        let hugeFile = hugeDir.appendingPathComponent("state.json")
        let hugeData = Data(repeating: 0x20, count: StateLimits.maximumJSONBytes + 1)
        try hugeData.write(to: hugeFile)
        let huge = ProjectStore(directory: hugeDir)
        try check(huge.persistenceError != nil && huge.addProject(name: "Refusé") == nil, "Oversized file is read-only")
        try check(try Data(contentsOf: hugeFile) == hugeData, "Oversized raw file remains untouched")
        try check(try FileManager.default.contentsOfDirectory(atPath: hugeDir.path) == ["state.json"], "Oversized raw file is not duplicated into backups")
        let exactFile = directory("exact-boundary")
        try FileManager.default.createDirectory(at: exactFile, withIntermediateDirectories: true)
        var exactData = Data("{}".utf8)
        exactData.append(Data(repeating: 0x20, count: StateLimits.maximumJSONBytes - 2))
        let exactURL = exactFile.appendingPathComponent("state.json")
        try exactData.write(to: exactURL)
        try check(try LocalStateFile.read(from: exactURL)?.count == StateLimits.maximumJSONBytes, "Bounded reader accepts exact byte boundary")
        var refusedLargeWrite = false
        do { try LocalStateFile.write(hugeData, to: exactURL) } catch { refusedLargeWrite = true }
        try check(refusedLargeWrite && (try Data(contentsOf: exactURL)) == exactData, "Oversized write refuses before replacing original")

        let target = root.appendingPathComponent("symlink-target.json")
        let protectedData = Data("{\"projects\":[]}".utf8)
        try protectedData.write(to: target)
        let linkedDir = directory("linked-state")
        try FileManager.default.createDirectory(at: linkedDir, withIntermediateDirectories: true)
        let linkedState = linkedDir.appendingPathComponent("state.json")
        try FileManager.default.createSymbolicLink(at: linkedState, withDestinationURL: target)
        let linked = ProjectStore(directory: linkedDir)
        try check(linked.persistenceError != nil && linked.addProject(name: "Refusé") == nil, "Symbolic state link is rejected")
        try check(try Data(contentsOf: target) == protectedData, "Symbolic-link target unchanged")
        try check(try FileManager.default.destinationOfSymbolicLink(atPath: linkedState.path) == target.path, "Rejected symbolic link itself remains intact")
        let folderTarget = try writeFixture("directory-target", "{}")
        let folderLink = directory("directory-link")
        try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: folderTarget)
        let linkedFolder = ProjectStore(directory: folderLink)
        try check(linkedFolder.persistenceError != nil && linkedFolder.addProject(name: "Refusé") == nil, "Final data-directory symbolic link is rejected")
        try check(try String(contentsOf: folderTarget.appendingPathComponent("state.json"), encoding: .utf8) == "{}", "Directory-link target unchanged")
        let hardDir = directory("hard-linked-state")
        try FileManager.default.createDirectory(at: hardDir, withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: target, to: hardDir.appendingPathComponent("state.json"))
        let hard = ProjectStore(directory: hardDir)
        try check(hard.persistenceError != nil && hard.addProject(name: "Refusé") == nil, "Hard-linked state is rejected")
        try check(try Data(contentsOf: target) == protectedData, "Hard-link target unchanged")
        let fifoDir = directory("fifo-state")
        try FileManager.default.createDirectory(at: fifoDir, withIntermediateDirectories: true)
        try check(mkfifo(fifoDir.appendingPathComponent("state.json").path, 0o600) == 0, "Disposable FIFO fixture created")
        let fifo = ProjectStore(directory: fifoDir)
        try check(fifo.persistenceError != nil && fifo.addProject(name: "Refusé") == nil, "FIFO is rejected without waiting for a writer")
        let unsafeDir = try writeFixture("shared-directory", "{}")
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: unsafeDir.path)
        let shared = ProjectStore(directory: unsafeDir)
        try check(shared.persistenceError != nil && shared.addProject(name: "Refusé") == nil, "Shared writable data directory is rejected")
        try check(try String(contentsOf: unsafeDir.appendingPathComponent("state.json"), encoding: .utf8) == "{}", "Unsafe-directory original unchanged")
        let changed = ProjectStore(directory: directory("changed-after-load"))
        let changedID = changed.addProject(name: "Conservé")!
        try FileManager.default.removeItem(at: changed.dataURL)
        try FileManager.default.createSymbolicLink(at: changed.dataURL, withDestinationURL: target)
        changed.setPosition(id: changedID, position: .right)
        try check(changed.state.projects[0].position == .left && changed.persistenceError != nil, "Unsafe replacement between load and write is rejected")
        try check(try Data(contentsOf: target) == protectedData, "Write-time symbolic-link target unchanged")

        checks += try NoteTests.run(root: root)
        checks += try InitialSetupTests.run(root: root)
        checks += try PanelModeTests.run(root: root)
        print("PASS: \(checks) behavioral assertions (initial setup, panel modes, model, notes, migrations, inheritance, persistence, limits, private permissions and unsafe local files).")
    }
}
