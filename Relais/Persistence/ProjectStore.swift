import Combine
import Darwin
import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var state = AppState()
    @Published private(set) var persistenceError: String?

    let dataURL: URL
    private var isReadOnly = false

    var needsInitialSetup: Bool { !isReadOnly && !state.initialSetupCompleted }
    var isDataUnavailable: Bool { isReadOnly }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                         in: .userDomainMask)[0]
            .appendingPathComponent("Relais", isDirectory: true)
        dataURL = base.appendingPathComponent("state.json", isDirectory: false)
        load()
    }

    /// Both labels and completion are persisted in the same atomic write.
    @discardableResult
    func completeInitialSetup(labels: PositionLabels) -> Bool {
        guard needsInitialSetup else { return false }
        guard labels.isValidForInitialSetup else {
            persistenceError = "Choisissez deux noms distincts et non vides, de \(StateLimits.maximumLabelBytes) octets UTF-8 maximum chacun."
            return false
        }
        return update {
            $0.globalLabels = labels.normalizedForSetup
            $0.initialSetupCompleted = true
            $0.panelVisible = true
        }
    }

    @discardableResult
    func addProject(name: String) -> UUID? {
        guard accepts({ try StateLimits.validateNameSize(name) }) else { return nil }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let project = RelayProject(name: cleaned)
        return update { $0.projects.append(project) } ? project.id : nil
    }

    func renameProject(id: UUID, name: String) {
        guard accepts({ try StateLimits.validateNameSize(name) }) else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateProject(id: id) { $0.name = cleaned }
    }

    func deleteProject(id: UUID) {
        update { $0.projects.removeAll { $0.id == id } }
    }

    func setPosition(id: UUID, position: RelayPosition) {
        updateProject(id: id) { $0.position = position }
    }

    func setCustomLabels(id: UUID, labels: PositionLabels?) {
        if let labels, !accepts({ try StateLimits.validateLabelSizes(labels) }) { return }
        guard labels == nil || labels!.isValid else { return }
        updateProject(id: id) { $0.customLabels = labels?.trimmed }
    }

    func setGlobalLabels(_ labels: PositionLabels) {
        guard accepts({ try StateLimits.validateLabelSizes(labels) }) else { return }
        guard labels.isValid else { return }
        update { $0.globalLabels = labels.trimmed }
    }

    /// Inserts the dragged project before target; nil appends it after the final row.
    func moveProject(id: UUID, before target: UUID?) {
        guard id != target else { return }
        update { state in
            guard let index = state.projects.firstIndex(where: { $0.id == id }),
                  target == nil || state.projects.contains(where: { $0.id == target }) else { return }
            let project = state.projects.remove(at: index)
            let destination = target.flatMap { targetID in
                state.projects.firstIndex(where: { $0.id == targetID })
            } ?? state.projects.endIndex
            state.projects.insert(project, at: destination)
        }
    }

    func labels(for project: RelayProject) -> PositionLabels {
        project.customLabels ?? state.globalLabels
    }

    func setWindowFrame(_ frame: SavedWindowFrame, mode: PanelMode? = nil) {
        guard state.initialSetupCompleted, frame.isValid else { return }
        let targetMode = mode ?? state.panelMode
        update {
            switch targetMode {
            case .expanded: $0.windowFrame = frame
            case .compact: $0.compactWindowFrame = frame
            }
        }
    }

    @discardableResult
    func setPanelMode(_ mode: PanelMode) -> Bool {
        guard state.initialSetupCompleted else { return false }
        return update { $0.panelMode = mode }
    }

    func setPanelVisible(_ visible: Bool) {
        guard state.initialSetupCompleted else { return }
        update { $0.panelVisible = visible }
    }

    @discardableResult
    func addNote(projectID: UUID, text: String) -> UUID? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let project = state.projects.first(where: { $0.id == projectID }) else { return nil }
        let greatestOrder = project.notes.map(\.order).max() ?? -1
        let note = RelayNote(text: cleaned, order: greatestOrder == Int.max ? Int.max : greatestOrder + 1)
        return updateProject(id: projectID) { $0.notes.append(note) } ? note.id : nil
    }

    @discardableResult
    func updateNote(projectID: UUID, noteID: UUID, text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let project = state.projects.first(where: { $0.id == projectID }),
              let index = project.notes.firstIndex(where: { $0.id == noteID }) else { return false }
        return updateProject(id: projectID) { $0.notes[index].text = cleaned }
    }

    @discardableResult
    func deleteNote(projectID: UUID, noteID: UUID) -> RelayNote? {
        guard let project = state.projects.first(where: { $0.id == projectID }),
              let note = project.notes.first(where: { $0.id == noteID }) else { return nil }
        return updateProject(id: projectID) { $0.notes.removeAll { $0.id == noteID } } ? note : nil
    }

    /// Restores the exact identity, pin and order for a simple Undo operation.
    @discardableResult
    func restoreNote(projectID: UUID, note: RelayNote) -> Bool {
        guard let project = state.projects.first(where: { $0.id == projectID }),
              !project.notes.contains(where: { $0.id == note.id }) else { return false }
        return updateProject(id: projectID) { $0.notes.append(note) }
    }

    @discardableResult
    func setNotePinned(projectID: UUID, noteID: UUID, isPinned: Bool) -> Bool {
        guard let project = state.projects.first(where: { $0.id == projectID }),
              let index = project.notes.firstIndex(where: { $0.id == noteID }) else { return false }
        return updateProject(id: projectID) { $0.notes[index].isPinned = isPinned }
    }

    @discardableResult
    private func updateProject(id: UUID, mutation: (inout RelayProject) -> Void) -> Bool {
        update { state in
            guard let index = state.projects.firstIndex(where: { $0.id == id }) else { return }
            mutation(&state.projects[index])
        }
    }

    private func accepts(_ validation: () throws -> Void) -> Bool {
        guard !isReadOnly else { return false }
        do { try validation(); return true }
        catch { persistenceError = error.localizedDescription; return false }
    }

    /// Commit to disk before publishing. If a write fails, the UI retains the last saved state.
    @discardableResult
    private func update(_ mutation: (inout AppState) -> Void) -> Bool {
        guard !isReadOnly else { return false }
        var next = state
        mutation(&next)
        guard next != state else { return true }
        do {
            try StateLimits.validate(next)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(next)
            try LocalStateFile.write(data, to: dataURL)
            state = next
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Sauvegarde impossible. La modification n’a pas été appliquée : \(error.localizedDescription)"
            return false
        }
    }

    private func load() {
        let data: Data
        do {
            guard let contents = try LocalStateFile.read(from: dataURL) else { return }
            data = contents
        } catch {
            preserveReadOnly(error: error)
            return
        }
        do {
            // Read the version before decoding the rest. A future app may change every field.
            struct Version: Decodable { let schemaVersion: Int? }
            let version = try JSONDecoder().decode(Version.self, from: data).schemaVersion ?? 1
            guard version <= AppState.currentSchemaVersion else {
                isReadOnly = true
                persistenceError = "Ces données proviennent d’une version plus récente de Relais. Elles sont conservées ; utilisez cette version pour les ouvrir."
                return
            }
            let recovery = StateDecodingRecovery()
            let decoder = JSONDecoder()
            decoder.userInfo[.stateRecovery] = recovery
            var loaded = try decoder.decode(AppState.self, from: data)
            try StateLimits.validate(loaded)
            loaded.normalize()
            state = loaded
            if recovery.notesNeeded || recovery.panelPreferencesNeeded {
                // A bad note or window preference must never discard projects.
                // Preserve all original bytes, including any unreadable note, before
                // allowing the recovered projects and notes to be changed.
                let prefix = recovery.panelPreferencesNeeded ? "state.preferences-recovery-" : "state.notes-recovery-"
                let backup = dataURL.deletingLastPathComponent()
                    .appendingPathComponent("\(prefix)\(UUID().uuidString).json")
                do {
                    try LocalStateFile.write(data, to: backup, replacing: false)
                    persistenceError = "Des notes ou préférences de fenêtre ont été récupérées. Les projets sont conservés et le fichier original est sauvegardé dans \(backup.lastPathComponent)."
                } catch {
                    isReadOnly = true
                    persistenceError = "Des notes ou préférences de fenêtre sont illisibles. Les projets restent affichés, mais les modifications sont bloquées car la copie de sécurité a échoué. Le fichier original est conservé."
                }
            }
        } catch let error as StateLimitError {
            preserveReadOnly(error: error)
        } catch {
            preserveUnreadableFile(data: data)
        }
    }

    private func preserveReadOnly(error: Error) {
        isReadOnly = true
        persistenceError = "Les données ne sont pas ouvertes : \(error.localizedDescription) Le fichier original est conservé et les modifications sont bloquées."
    }

    private func preserveUnreadableFile(data: Data) {
        // Even a successful backup does not authorize replacing an unreadable
        // installation with a fresh setup. Keep it blocked until it is repaired.
        isReadOnly = true
        let backup = dataURL.deletingLastPathComponent()
            .appendingPathComponent("state.invalid-\(UUID().uuidString).json")
        do {
            try LocalStateFile.write(data, to: backup, replacing: false)
            persistenceError = "Les données n’ont pas pu être lues. Une copie intacte a été conservée dans \(backup.lastPathComponent). Le fichier original est conservé et les modifications sont bloquées."
        } catch {
            isReadOnly = true
            persistenceError = "Les données sont illisibles et leur copie de sécurité a échoué. Le fichier original est conservé ; les modifications sont bloquées."
        }
    }
}

/// No polling or dependencies: bounded descriptor reads and private atomic writes on demand.
/// The final directory and file are opened without following symbolic links.
enum LocalStateFile {
    private static func systemError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private static var unsafeFile: StateLimitError {
        .exceeded("Le chemin de données doit être privé, ordinaire, sans lien symbolique et appartenir à votre compte.")
    }

    private static func directory(at url: URL, create: Bool) throws -> Int32? {
        if create {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if !create && errno == ENOENT { return nil }
            throw systemError()
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let error = systemError(); Darwin.close(descriptor); throw error
        }
        guard info.st_uid == getuid(), info.st_mode & mode_t(0o022) == 0 else {
            Darwin.close(descriptor); throw unsafeFile
        }
        if create, fchmod(descriptor, 0o700) != 0 {
            let error = systemError(); Darwin.close(descriptor); throw error
        }
        return descriptor
    }

    private static func validate(_ info: stat) throws {
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1 else { throw unsafeFile }
        guard info.st_size >= 0, info.st_size <= off_t(StateLimits.maximumJSONBytes) else {
            throw StateLimitError.exceeded("Le fichier de données dépasse la limite de 2 Mio.")
        }
    }

    static func read(from url: URL) throws -> Data? {
        guard let folder = try directory(at: url.deletingLastPathComponent(), create: false) else { return nil }
        defer { Darwin.close(folder) }
        // O_NONBLOCK avoids waiting if a regular file was replaced with a FIFO.
        let descriptor = openat(folder, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw systemError()
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw systemError() }
        try validate(info)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        // Read at most the limit plus one byte, even if the file grows after fstat.
        while data.count <= StateLimits.maximumJSONBytes {
            let amount = min(65_536, StateLimits.maximumJSONBytes + 1 - data.count)
            guard let chunk = try handle.read(upToCount: amount), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= StateLimits.maximumJSONBytes else {
            throw StateLimitError.exceeded("Le fichier de données dépasse la limite de 2 Mio.")
        }
        guard fstat(descriptor, &info) == 0 else { throw systemError() }
        try validate(info)
        return data
    }

    static func write(_ data: Data, to url: URL, replacing: Bool = true) throws {
        guard data.count <= StateLimits.maximumJSONBytes else {
            throw StateLimitError.exceeded("Le fichier de données dépasse la limite de 2 Mio.")
        }
        guard let folder = try directory(at: url.deletingLastPathComponent(), create: true) else { throw unsafeFile }
        defer { Darwin.close(folder) }
        var existing = stat()
        if fstatat(folder, url.lastPathComponent, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
            try validate(existing)
            guard replacing else { throw unsafeFile }
        } else if errno != ENOENT { throw systemError() }
        let temporary = ".state-\(UUID().uuidString).tmp"
        let descriptor = openat(folder, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw systemError() }
        defer { Darwin.close(descriptor); unlinkat(folder, temporary, 0) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard renameat(folder, temporary, folder, url.lastPathComponent) == 0 else { throw systemError() }
    }
}
