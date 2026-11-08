import Foundation

/// Generous limits for a compact local utility, measured in bytes to bound Unicode input too.
enum StateLimits {
    static let maximumJSONBytes = 2 * 1_024 * 1_024
    static let maximumProjects = 500
    static let maximumProjectNameBytes = 1_024
    static let maximumLabelBytes = 512

    static func validateNameSize(_ name: String) throws {
        guard name.utf8.count <= maximumProjectNameBytes else {
            throw StateLimitError.exceeded("Un nom de projet est limité à \(maximumProjectNameBytes) octets UTF-8.")
        }
    }

    static func validateLabelSizes(_ labels: PositionLabels) throws {
        guard labels.left.utf8.count <= maximumLabelBytes,
              labels.right.utf8.count <= maximumLabelBytes else {
            throw StateLimitError.exceeded("Chaque libellé est limité à \(maximumLabelBytes) octets UTF-8.")
        }
    }

    static func validate(_ state: AppState) throws {
        guard state.projects.count <= maximumProjects else {
            throw StateLimitError.exceeded("Relais accepte jusqu’à \(maximumProjects) projets.")
        }
        try validateLabelSizes(state.globalLabels)
        for project in state.projects {
            try validateNameSize(project.name)
            if let labels = project.customLabels { try validateLabelSizes(labels) }
        }
    }
}

enum StateLimitError: LocalizedError {
    case exceeded(String)
    var errorDescription: String? {
        switch self { case .exceeded(let message): return message }
    }
}

/// State is deliberately independent of the names displayed in the interface.
enum RelayPosition: String, Codable, CaseIterable {
    case left
    case right

    var opposite: RelayPosition { self == .left ? .right : .left }
}

struct PositionLabels: Codable, Equatable {
    var left: String
    var right: String

    init(left: String, right: String) {
        self.left = left
        self.right = right
    }

    private enum CodingKeys: String, CodingKey { case left, right }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        left = try values.decode(String.self, forKey: .left)
        right = try values.decode(String.self, forKey: .right)
        try StateLimits.validateLabelSizes(self)
    }

    /// Neutral internal fallback only; the first-run fields themselves are empty.
    static let defaults = PositionLabels(left: "Position gauche", right: "Position droite")

    func label(for position: RelayPosition) -> String {
        position == .left ? left : right
    }

    var trimmed: PositionLabels {
        PositionLabels(left: left.trimmingCharacters(in: .whitespacesAndNewlines),
                       right: right.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var isValid: Bool { !trimmed.left.isEmpty && !trimmed.right.isEmpty }

    var normalizedForSetup: PositionLabels {
        func normalize(_ text: String) -> String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return PositionLabels(left: normalize(left), right: normalize(right))
    }

    var isValidForInitialSetup: Bool {
        let names = normalizedForSetup
        return names.isValid
            && names.left.utf8.count <= StateLimits.maximumLabelBytes
            && names.right.utf8.count <= StateLimits.maximumLabelBytes
            && names.left.compare(names.right, options: [.caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX")) != .orderedSame
    }
}

/// A note's order is independent of pinning, so unpinning restores its original place.
struct RelayNote: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var isPinned: Bool
    var order: Int

    init(id: UUID = UUID(), text: String, isPinned: Bool = false, order: Int = 0) {
        self.id = id
        self.text = text
        self.isPinned = isPinned
        self.order = order
    }

    private enum CodingKeys: String, CodingKey { case id, text, isPinned, order }

    init(from decoder: Decoder) throws { try self.init(from: decoder, defaultOrder: 0) }

    fileprivate init(from decoder: Decoder, defaultOrder: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decode(String.self, forKey: .text)
        id = (try? values.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        isPinned = (try? values.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? false
        order = (try? values.decodeIfPresent(Int.self, forKey: .order)) ?? defaultOrder
        // Missing metadata is compatible with an intermediate single-note format.
        // Invalid metadata is repaired, and the exact original file is backed up.
        if (values.contains(.id) && (try? values.decodeIfPresent(UUID.self, forKey: .id)) == nil)
            || (values.contains(.isPinned) && (try? values.decodeIfPresent(Bool.self, forKey: .isPinned)) == nil)
            || (values.contains(.order) && (try? values.decodeIfPresent(Int.self, forKey: .order)) == nil) {
            decoder.stateRecovery?.notesNeeded = true
        }
    }
}

/// Shared by nested decoders; never persisted or included in model equality.
/// JSONDecoder requires Sendable userInfo values. The lock protects the only
/// mutable property even if a caller shares this collector across decoders.
final class StateDecodingRecovery: @unchecked Sendable {
    private let lock = NSLock()
    private var noteRecoveryNeeded = false
    private var preferenceRecoveryNeeded = false
    var notesNeeded: Bool {
        get { lock.lock(); defer { lock.unlock() }; return noteRecoveryNeeded }
        set { lock.lock(); defer { lock.unlock() }; noteRecoveryNeeded = newValue }
    }
    var panelPreferencesNeeded: Bool {
        get { lock.lock(); defer { lock.unlock() }; return preferenceRecoveryNeeded }
        set { lock.lock(); defer { lock.unlock() }; preferenceRecoveryNeeded = newValue }
    }
}

extension CodingUserInfoKey {
    static let stateRecovery = CodingUserInfoKey(rawValue: "org.relaisapp.stateRecovery")!
}

private extension Decoder {
    var stateRecovery: StateDecodingRecovery? { userInfo[.stateRecovery] as? StateDecodingRecovery }
}

struct RelayProject: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var position: RelayPosition
    /// nil means dynamic inheritance; global names are never copied into a project.
    var customLabels: PositionLabels?
    var notes: [RelayNote]

    init(id: UUID = UUID(), name: String, position: RelayPosition = .left,
         customLabels: PositionLabels? = nil, notes: [RelayNote] = []) {
        self.id = id
        self.name = name
        self.position = position
        self.customLabels = customLabels
        self.notes = notes
    }

    var orderedNotes: [RelayNote] {
        notes.enumerated().sorted { lhs, rhs in
            if lhs.element.isPinned != rhs.element.isPinned { return lhs.element.isPinned }
            if lhs.element.order != rhs.element.order { return lhs.element.order < rhs.element.order }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private enum CodingKeys: String, CodingKey { case id, name, position, customLabels, notes, note, notePinned }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        try StateLimits.validateNameSize(name)
        let savedPosition = try values.decodeIfPresent(String.self, forKey: .position)
        position = savedPosition.flatMap(RelayPosition.init(rawValue:)) ?? .left
        customLabels = try values.decodeIfPresent(PositionLabels.self, forKey: .customLabels)
        notes = []
        if values.contains(.notes), (try? values.decodeNil(forKey: .notes)) != true {
            if var entries = try? values.nestedUnkeyedContainer(forKey: .notes) {
                while !entries.isAtEnd {
                    let child = try entries.superDecoder()
                    if let note = try? RelayNote(from: child, defaultOrder: notes.count) {
                        notes.append(note)
                    } else if let text = try? child.singleValueContainer().decode(String.self) {
                        notes.append(RelayNote(text: text, order: notes.count))
                        decoder.stateRecovery?.notesNeeded = true
                    } else {
                        decoder.stateRecovery?.notesNeeded = true
                    }
                }
            } else {
                decoder.stateRecovery?.notesNeeded = true
            }
        }
        // A previous experimental version may have stored a single string or object.
        if values.contains(.note), (try? values.decodeNil(forKey: .note)) != true {
            let child = try values.superDecoder(forKey: .note)
            let legacy: RelayNote?
            if let text = try? child.singleValueContainer().decode(String.self) {
                let pinned = (try? values.decodeIfPresent(Bool.self, forKey: .notePinned)) ?? false
                legacy = text.isEmpty ? nil : RelayNote(text: text, isPinned: pinned, order: notes.count)
            } else if let note = try? RelayNote(from: child, defaultOrder: notes.count) {
                legacy = note
            } else {
                legacy = nil
                decoder.stateRecovery?.notesNeeded = true
            }
            if let legacy, !notes.contains(where: { $0.id == legacy.id || $0.text == legacy.text }) {
                notes.append(legacy)
            }
        }
        var identifiers = Set<UUID>()
        for index in notes.indices {
            if !identifiers.insert(notes[index].id).inserted {
                notes[index].id = UUID()
                decoder.stateRecovery?.notesNeeded = true
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(position, forKey: .position)
        try values.encodeIfPresent(customLabels, forKey: .customLabels)
        try values.encode(notes, forKey: .notes)
    }
}

enum PanelMode: String, Codable {
    case expanded
    case compact
}

struct SavedWindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
}

struct AppState: Codable, Equatable {
    static let currentSchemaVersion = 4

    var schemaVersion: Int
    /// Array order is the display order, so there is no second order field to desynchronize.
    var projects: [RelayProject]
    var globalLabels: PositionLabels
    var windowFrame: SavedWindowFrame?
    var compactWindowFrame: SavedWindowFrame?
    var panelMode: PanelMode
    var panelVisible: Bool
    var initialSetupCompleted: Bool

    init(schemaVersion: Int = currentSchemaVersion, projects: [RelayProject] = [],
         globalLabels: PositionLabels = .defaults, windowFrame: SavedWindowFrame? = nil,
         panelVisible: Bool = true, initialSetupCompleted: Bool = false,
         panelMode: PanelMode = .expanded, compactWindowFrame: SavedWindowFrame? = nil) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.globalLabels = globalLabels
        self.windowFrame = windowFrame
        self.compactWindowFrame = compactWindowFrame
        self.panelMode = panelMode
        self.panelVisible = panelVisible
        self.initialSetupCompleted = initialSetupCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, projects, globalLabels, windowFrame, compactWindowFrame, panelMode, panelVisible, initialSetupCompleted
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        projects = []
        if values.contains(.projects), !(try values.decodeNil(forKey: .projects)) {
            var entries = try values.nestedUnkeyedContainer(forKey: .projects)
            if let count = entries.count, count > StateLimits.maximumProjects {
                throw StateLimitError.exceeded("Relais accepte jusqu’à \(StateLimits.maximumProjects) projets.")
            }
            while !entries.isAtEnd {
                guard projects.count < StateLimits.maximumProjects else {
                    throw StateLimitError.exceeded("Relais accepte jusqu’à \(StateLimits.maximumProjects) projets.")
                }
                projects.append(try entries.decode(RelayProject.self))
            }
        }
        globalLabels = try values.decodeIfPresent(PositionLabels.self, forKey: .globalLabels) ?? .defaults
        windowFrame = Self.decodeFrame(from: values, forKey: .windowFrame, decoder: decoder)
        compactWindowFrame = Self.decodeFrame(from: values, forKey: .compactWindowFrame, decoder: decoder)
        if values.contains(.panelMode) {
            do { panelMode = try values.decode(PanelMode.self, forKey: .panelMode) }
            catch {
                panelMode = .expanded
                decoder.stateRecovery?.panelPreferencesNeeded = true
            }
        } else {
            panelMode = .expanded
        }
        panelVisible = try values.decodeIfPresent(Bool.self, forKey: .panelVisible) ?? true
        if schemaVersion < 3 {
            // A valid old file is an existing installation, including zero projects.
            initialSetupCompleted = true
        } else {
            // A missing/invalid marker in a new-format file is corruption, not
            // permission to reconfigure or replace the user's existing state.
            initialSetupCompleted = try values.decode(Bool.self, forKey: .initialSetupCompleted)
        }
    }

    private static func decodeFrame(from values: KeyedDecodingContainer<CodingKeys>,
                                    forKey key: CodingKeys, decoder: Decoder) -> SavedWindowFrame? {
        guard values.contains(key), (try? values.decodeNil(forKey: key)) != true else { return nil }
        do {
            let frame = try values.decode(SavedWindowFrame.self, forKey: key)
            guard frame.isValid else {
                decoder.stateRecovery?.panelPreferencesNeeded = true
                return nil
            }
            return frame
        } catch {
            decoder.stateRecovery?.panelPreferencesNeeded = true
            return nil
        }
    }

    /// Repairs recoverable field errors while keeping IDs, positions and valid custom labels.
    mutating func normalize() {
        globalLabels = globalLabels.isValid ? globalLabels.trimmed : .defaults
        var knownIDs = Set<UUID>()
        projects = projects.compactMap { project in
            var result = project
            result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.name.isEmpty, knownIDs.insert(result.id).inserted else { return nil }
            if let custom = result.customLabels {
                result.customLabels = custom.isValid ? custom.trimmed : nil
            }
            return result
        }
        if let frame = windowFrame, !frame.isValid { windowFrame = nil }
        if let frame = compactWindowFrame, !frame.isValid { compactWindowFrame = nil }
        schemaVersion = Self.currentSchemaVersion
    }
}
