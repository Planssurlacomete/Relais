import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Distinguish the stable property wrapper from the SDK 27 State macro.
private typealias PanelState<Value> = SwiftUI.State<Value>

struct PanelView: View {
    @ObservedObject var store: ProjectStore
    var onReduce: () -> Void
    var onRestore: () -> Void
    var onSettings: () -> Void
    var onBeginEditing: () -> Void
    var onEndEditing: () -> Void = {}
    /// Natural content height, independent of the scroll view's visible viewport.
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    var noteUndoManager: UndoManager? = nil
    @PanelState<ProjectEditorRequest?> private var editor: ProjectEditorRequest?
    @PanelState<RelayProject?> private var deletion: RelayProject?
    @PanelState<UUID?> private var dropTarget: UUID?
    @PanelState<NoteEditorTarget?> private var noteEditor: NoteEditorTarget?
    @PanelState<String> private var noteDraft = ""
    @FocusState private var noteFieldFocused: Bool

    var body: some View {
        Group {
            if store.state.panelMode == .compact {
                compactPanel
            } else {
                expandedPanel
            }
        }
        .background(Color(red: 0.065, green: 0.069, blue: 0.078))
        .clipShape(RoundedRectangle(cornerRadius: store.state.panelMode == .compact ? 18 : 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: store.state.panelMode == .compact ? 18 : 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onPreferenceChange(PanelHeightPreference.self) { heights in
            guard store.state.panelMode == .expanded else { return }
            // Header 44, divider 1, footer 20. Notes contribute only their actual height.
            onContentHeightChange(65 + (heights[.body] ?? 112) + (heights[.error] ?? 0))
        }
        .onChange(of: store.state.panelMode) { _, mode in
            if mode == .compact {
                // The same view owns the draft in both modes. Reducing only ends
                // keyboard focus; the text is still present on restoration.
                noteFieldFocused = false
                onEndEditing()
            }
        }
        .sheet(item: $editor, onDismiss: onEndEditing) { request in
            ProjectEditorView(request: request, store: store)
                .preferredColorScheme(.dark)
        }
        .alert("Supprimer ce projet ?", isPresented: Binding(
            get: { deletion != nil },
            set: { if !$0 { deletion = nil; onEndEditing() } }
        ), presenting: deletion) { project in
            Button("Annuler", role: .cancel) { deletion = nil; onEndEditing() }
            Button("Supprimer", role: .destructive) {
                store.deleteProject(id: project.id)
                deletion = nil
                onEndEditing()
            }
        } message: { project in
            Text("« \(project.name) » sera supprimé de Relais.")
        }
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            if let error = store.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
                    .help(error)
                    .padding(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .reportPanelHeight(.error)
            }
            if store.state.projects.isEmpty {
                emptyState
                    .frame(height: 112)
                    .reportPanelHeight(.body)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(store.state.projects) { project in
                            projectRow(project)
                                .onDrop(of: [UTType.text], isTargeted: targetBinding(project.id)) { providers in
                                    acceptDrop(providers, before: project.id)
                                }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .reportPanelHeight(.body)
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: .infinity)
            }
            footer
                .contentShape(Rectangle())
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    acceptDrop(providers, before: nil)
                }
        }
        .frame(width: 248)
    }

    private var compactPanel: some View {
        HStack(spacing: 4) {
            HStack(spacing: 7) {
                RelaisIconView(size: 15).accessibilityHidden(true)
                Text("Relais")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.88))
                Spacer(minLength: 0)
            }
            .overlay { PanelDragArea().accessibilityHidden(true) }
            CompactRestoreButton(action: onRestore)
                .frame(width: 26, height: 28)
        }
        .padding(.leading, 13)
        .padding(.trailing, 7)
        .frame(width: 148, height: 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Relais, mode réduit")
        .accessibilityIdentifier("relais-compact-panel")
    }

    private var header: some View {
        HStack(spacing: 3) {
            HStack(spacing: 7) {
                RelaisIconView(size: 14).accessibilityHidden(true)
                Text("Relais")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.88))
                Spacer(minLength: 0)
            }
            .overlay { PanelDragArea().accessibilityHidden(true) }
            headerButton("plus", label: "Ajouter un projet", identifier: "add-project") {
                beginEditor(.init(mode: .add, name: "", labels: store.state.globalLabels))
            }
            headerButton("gearshape", label: "Réglages de Relais", identifier: "open-settings", action: onSettings)
            headerButton("minus", label: "Réduire Relais", identifier: "reduce-panel", action: onReduce)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func headerButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.65))
                .frame(width: 27, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            RelaisIconView(size: 25).accessibilityHidden(true)
            Text("À qui la main ?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.78))
            Button("Ajouter un projet") {
                beginEditor(.init(mode: .add, name: "", labels: store.state.globalLabels))
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color(red: 0.36, green: 0.68, blue: 1))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Circle().fill(Color(white: 0.45)).frame(width: 3, height: 3)
            Text(store.state.projects.isEmpty ? "Un projet, deux positions." : "Glisser pour réordonner")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.48))
            Spacer()
        }
        .padding(.horizontal, 15)
        .frame(height: 20)
    }

    private func projectRow(_ project: RelayProject) -> some View {
        let labels = store.labels(for: project)
        return VStack(alignment: .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.91))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(project.name)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 10)
                .onDrag { NSItemProvider(object: project.id.uuidString as NSString) }
            HStack(spacing: 8) {
                positionLabel(labels.left, position: .left, project: project, alignment: .trailing)
                MechanicalSwitch(
                    position: Binding(get: { project.position }, set: { store.setPosition(id: project.id, position: $0) }),
                    leftLabel: labels.left,
                    rightLabel: labels.right
                )
                .accessibilityIdentifier("switch-\(project.id.uuidString)")
                positionLabel(labels.right, position: .right, project: project, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            }
            .contextMenu { projectMenu(project) }
            if !project.orderedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(project.orderedNotes) { note in
                        noteRow(note, project: project)
                    }
                }
            }
            if noteEditor == NoteEditorTarget(projectID: project.id, noteID: nil) {
                inlineNoteEditor(projectID: project.id)
            } else {
                Button("+ Note") { beginNoteEditing(projectID: project.id, note: nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.53))
                    .frame(minHeight: 20, alignment: .leading)
                    .help("Ajouter une note à \(project.name)")
                    .accessibilityIdentifier("add-note-\(project.id.uuidString)")
            }
            Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 82)
        .contentShape(Rectangle())
        .background(dropTarget == project.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(project.name)
    }

    private func noteRow(_ note: RelayNote, project: RelayProject) -> some View {
        HStack(alignment: .top, spacing: 3) {
            if noteEditor == NoteEditorTarget(projectID: project.id, noteID: note.id) {
                inlineNoteEditor(projectID: project.id)
            } else {
                Button { beginNoteEditing(projectID: project.id, note: note) } label: {
                    Text(note.text)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.69))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(note.text)
                .accessibilityLabel(note.text)
                .accessibilityHint("Cliquer pour modifier la note")
                .accessibilityIdentifier("note-text-\(note.id.uuidString)")
            }
            HStack(spacing: 0) {
                NotePinButton(isPinned: note.isPinned, identifier: "pin-note-\(note.id.uuidString)") {
                    _ = store.setNotePinned(projectID: project.id, noteID: note.id, isPinned: !note.isPinned)
                }
                .frame(width: 20, height: 24)
                NoteDeleteButton(text: note.text, identifier: "delete-note-\(note.id.uuidString)") {
                    // Retain keyboard focus so the panel receives Cmd+Z after a first-mouse click.
                    onBeginEditing()
                    if noteEditor?.projectID == project.id && noteEditor?.noteID == note.id {
                        noteEditor = nil
                        noteDraft = ""
                        noteFieldFocused = false
                    }
                    NoteUndo.delete(projectID: project.id, noteID: note.id, store: store, manager: noteUndoManager)
                }
                .frame(width: 22, height: 24)
            }
            .padding(.trailing, -7)
        }
        .contextMenu {
            Button("Modifier…") { beginNoteEditing(projectID: project.id, note: note) }
        }
        .accessibilityElement(children: .contain)
    }

    private func inlineNoteEditor(projectID: UUID) -> some View {
        TextField("Votre note", text: $noteDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color(white: 0.86))
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.12)) }
            .focused($noteFieldFocused)
            .onSubmit { _ = commitNote() }
            .onExitCommand(perform: cancelNoteEditing)
            .help("Entrée pour enregistrer · Échap pour annuler")
            .accessibilityLabel("Texte de la note")
            .accessibilityIdentifier("note-editor-\(projectID.uuidString)")
    }

    private func beginNoteEditing(projectID: UUID, note: RelayNote?) {
        let target = NoteEditorTarget(projectID: projectID, noteID: note?.id)
        guard noteEditor != target else { noteFieldFocused = true; return }
        // Keep an unsaved draft visible when its save fails.
        if noteEditor != nil && !commitNote() { return }
        onBeginEditing()
        noteDraft = note?.text ?? ""
        noteEditor = target
        DispatchQueue.main.async { noteFieldFocused = true }
    }

    @discardableResult private func commitNote() -> Bool {
        guard let target = noteEditor else { return true }
        guard !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let succeeded: Bool
        if let noteID = target.noteID {
            succeeded = store.updateNote(projectID: target.projectID, noteID: noteID, text: noteDraft)
        } else {
            succeeded = store.addNote(projectID: target.projectID, text: noteDraft) != nil
        }
        guard succeeded else { return false }
        cancelNoteEditing()
        return true
    }

    private func cancelNoteEditing() {
        noteEditor = nil
        noteDraft = ""
        noteFieldFocused = false
        onEndEditing()
    }

    private func positionLabel(_ title: String, position: RelayPosition, project: RelayProject, alignment: Alignment) -> some View {
        let active = project.position == position
        return Button { store.setPosition(id: project.id, position: position) } label: {
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.white : Color(white: 0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel("Donner la main à \(title)")
        .accessibilityValue(active ? "Position active" : "Position inactive")
    }

    @ViewBuilder private func projectMenu(_ project: RelayProject) -> some View {
        Button("Renommer…") {
            beginEditor(.init(mode: .rename(project.id), name: project.name, labels: store.labels(for: project)))
        }
        Button("Personnaliser les positions…") {
            beginEditor(.init(mode: .labels(project.id), name: project.name, labels: store.labels(for: project)))
        }
        if project.customLabels != nil {
            Button("Rétablir les noms globaux") { store.setCustomLabels(id: project.id, labels: nil) }
        }
        Divider()
        Button("Monter") { moveUp(project) }
            .disabled(store.state.projects.first?.id == project.id)
        Button("Descendre") { moveDown(project) }
            .disabled(store.state.projects.last?.id == project.id)
        Divider()
        Button("Supprimer…", role: .destructive) {
            onBeginEditing()
            deletion = project
        }
    }

    private func beginEditor(_ request: ProjectEditorRequest) {
        onBeginEditing()
        editor = request
    }

    private func moveUp(_ project: RelayProject) {
        guard let index = store.state.projects.firstIndex(where: { $0.id == project.id }), index > 0 else { return }
        store.moveProject(id: project.id, before: store.state.projects[index - 1].id)
    }

    private func moveDown(_ project: RelayProject) {
        guard let index = store.state.projects.firstIndex(where: { $0.id == project.id }), index + 1 < store.state.projects.count else { return }
        let target = index + 2 < store.state.projects.count ? store.state.projects[index + 2].id : nil
        store.moveProject(id: project.id, before: target)
    }

    private func targetBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { dropTarget == id }, set: { if $0 { dropTarget = id } else if dropTarget == id { dropTarget = nil } })
    }

    private func acceptDrop(_ providers: [NSItemProvider], before target: UUID?) -> Bool {
        // Only IDs already in this list are accepted; a drop never imports data.
        guard let provider = providers.first else { return false }
        guard provider.canLoadObject(ofClass: NSString.self) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, let id = UUID(uuidString: value) else { return }
            DispatchQueue.main.async {
                guard store.state.projects.contains(where: { $0.id == id }) else { return }
                store.moveProject(id: id, before: target)
                dropTarget = nil
            }
        }
        return true
    }
}

private struct NoteEditorTarget: Equatable {
    let projectID: UUID
    let noteID: UUID?
}

private enum PanelHeightPart: Hashable { case body, error }

private struct PanelHeightPreference: PreferenceKey {
    static let defaultValue: [PanelHeightPart: CGFloat] = [:]
    static func reduce(value: inout [PanelHeightPart: CGFloat], nextValue: () -> [PanelHeightPart: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, height in height })
    }
}

private extension View {
    func reportPanelHeight(_ part: PanelHeightPart) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: PanelHeightPreference.self, value: [part: geometry.size.height])
            }
        }
    }
}

/// The tiny visible cross has a larger hit target and acts on the first click
/// while the nonactivating panel belongs to another application's workspace.
private final class FirstMouseNoteButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

/// Restoration is independent of the draggable title and never requests focus.
private struct CompactRestoreButton: NSViewRepresentable {
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = FirstMouseNoteButton(title: "", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Agrandir Relais")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        button.contentTintColor = NSColor(white: 0.68, alpha: 1)
        button.focusRingType = .none
        button.toolTip = "Agrandir Relais"
        button.setAccessibilityLabel("Agrandir Relais")
        button.setAccessibilityIdentifier("restore-panel")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.action = action }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
}

private struct NotePinButton: NSViewRepresentable {
    let isPinned: Bool
    let identifier: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = FirstMouseNoteButton(title: "", target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        let label = isPinned ? "Désépingler la note" : "Épingler la note"
        button.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .regular))
        button.contentTintColor = NSColor(white: isPinned ? 0.85 : 0.48, alpha: 1)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(isPinned ? 1 : 0)
        button.setAccessibilityIdentifier(identifier)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func clicked(_ sender: NSButton) {
            sender.window?.makeKey()
            sender.window?.makeFirstResponder(sender)
            action()
        }
    }
}

private struct NoteDeleteButton: NSViewRepresentable {
    let text: String
    let identifier: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = FirstMouseNoteButton(title: "×", target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryChange)
        button.font = .systemFont(ofSize: 15)
        button.contentTintColor = NSColor(white: 0.62, alpha: 1)
        button.focusRingType = .none
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = "Supprimer la note : \(text)"
        button.setAccessibilityLabel("Supprimer la note : \(text)")
        button.setAccessibilityIdentifier(identifier)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func clicked(_ sender: NSButton) {
            sender.window?.makeKey()
            sender.window?.makeFirstResponder(sender)
            action()
        }
    }

}

@MainActor enum NoteUndo {
    static func delete(projectID: UUID, noteID: UUID, store: ProjectStore, manager: UndoManager?) {
        guard let removed = store.deleteNote(projectID: projectID, noteID: noteID) else { return }
        manager?.registerUndo(withTarget: store) { [weak manager] target in
            restore(projectID: projectID, note: removed, store: target, manager: manager)
        }
        manager?.setActionName("Supprimer la note")
    }

    private static func restore(projectID: UUID, note: RelayNote, store: ProjectStore, manager: UndoManager?) {
        guard store.restoreNote(projectID: projectID, note: note) else { return }
        manager?.registerUndo(withTarget: store) { [weak manager] target in
            delete(projectID: projectID, noteID: note.id, store: target, manager: manager)
        }
        manager?.setActionName("Supprimer la note")
    }
}

private struct ProjectEditorRequest: Identifiable {
    enum Mode { case add, rename(UUID), labels(UUID) }
    let id = UUID()
    let mode: Mode
    let name: String
    let labels: PositionLabels
}

private struct ProjectEditorView: View {
    let request: ProjectEditorRequest
    @ObservedObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @PanelState<String> private var name: String
    @PanelState<String> private var left: String
    @PanelState<String> private var right: String
    @PanelState<String?> private var commitError: String?
    @FocusState private var focusedField: Field?
    private enum Field { case name, left, right }

    init(request: ProjectEditorRequest, store: ProjectStore) {
        self.request = request
        self.store = store
        _name = PanelState(initialValue: request.name)
        _left = PanelState(initialValue: request.labels.left)
        _right = PanelState(initialValue: request.labels.right)
    }

    private var isLabels: Bool { if case .labels = request.mode { return true }; return false }
    private var title: String {
        switch request.mode {
        case .add: return "Nouveau projet"
        case .rename: return "Renommer le projet"
        case .labels: return "Les deux positions"
        }
    }
    private var isValid: Bool {
        if isLabels { return !left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if isLabels {
                Text(request.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                VStack(alignment: .leading, spacing: 5) {
                    Text("À gauche").font(.caption).foregroundStyle(.secondary)
                    TextField("Nom de la position gauche", text: $left).focused($focusedField, equals: .left)
                        .accessibilityIdentifier("project-left-label")
                    Text("À droite").font(.caption).foregroundStyle(.secondary).padding(.top, 5)
                    TextField("Nom de la position droite", text: $right).focused($focusedField, equals: .right)
                        .accessibilityIdentifier("project-right-label")
                }
            } else {
                TextField("Nom du projet", text: $name).focused($focusedField, equals: .name)
                    .accessibilityIdentifier("project-name")
            }
            if let error = commitError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project-save-error")
            }
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(isLabels ? "Appliquer" : (request.name.isEmpty ? "Ajouter" : "Renommer"), action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 284)
        .onSubmit(commit)
        .onAppear { focusedField = isLabels ? .left : .name }
    }

    private func commit() {
        guard isValid else { return }
        commitError = nil
        let succeeded: Bool
        switch request.mode {
        case .add:
            succeeded = store.addProject(name: name) != nil
        case .rename(let id):
            store.renameProject(id: id, name: name)
            let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            succeeded = store.persistenceError == nil && store.state.projects.first(where: { $0.id == id })?.name == cleaned
        case .labels(let id):
            let labels = PositionLabels(left: left, right: right)
            store.setCustomLabels(id: id, labels: labels)
            succeeded = store.persistenceError == nil && store.state.projects.first(where: { $0.id == id })?.customLabels == labels.trimmed
        }
        guard succeeded else {
            commitError = store.persistenceError ?? "La modification n’a pas pu être appliquée. Votre saisie est conservée."
            return
        }
        dismiss()
    }
}

/// Drag only the title area: controls and project rows remain independently clickable.
private struct PanelDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
