import AppKit
import Darwin
import Foundation

/// Isolated first-launch probe. Its bundle ID and source directory are generated
/// for each run; it never opens the production application's legacy state file.
@main
@MainActor
struct SandboxProbe {
    private static var failures = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if condition() {
            print("PASS \(label)")
        } else {
            failures += 1
            print("FAIL \(label)")
        }
        fflush(stdout)
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 3,
              let bundleID = Bundle.main.bundleIdentifier,
              bundleID.hasPrefix("org.relaisapp.Relais.SecurityTest.") else {
            print("FAIL isolated probe invocation")
            exit(2)
        }
        let readCanary = URL(fileURLWithPath: CommandLine.arguments[1])
        let writeCanary = CommandLine.arguments[2]
        guard readCanary.lastPathComponent == "read-canary.txt",
              URL(fileURLWithPath: writeCanary).lastPathComponent == "write-canary.txt",
              readCanary.deletingLastPathComponent().lastPathComponent.hasPrefix("RelaisMigrationTest-") else {
            print("FAIL isolated probe canary arguments")
            exit(2)
        }

        let expected = AppState(
            projects: [RelayProject(
                id: UUID(uuidString: "D5CA5407-9B7F-4C58-83A9-2A0136514219")!,
                name: "Projet Alpha",
                position: .right,
                customLabels: PositionLabels(left: "Création", right: "Validation")
            )],
            globalLabels: PositionLabels(left: "Équipe A", right: "Équipe B"),
            windowFrame: SavedWindowFrame(x: 111, y: 222, width: 248, height: 230),
            panelVisible: false,
            initialSetupCompleted: true
        )
        let store = ProjectStore()
        let containerSuffix = "/Library/Containers/\(bundleID)/Data/Library/Application Support/Relais/state.json"
        check(store.dataURL.path.hasSuffix(containerSuffix), "default storage resolves inside isolated sandbox container")
        check(store.state == expected, "first-launch manifest migrates entire legacy fixture")
        check(store.persistenceError == nil, "migrated state loads without recovery warnings")

        let added = store.addProject(name: "Projet Bêta")
        check(added != nil, "sandbox allows atomic state writes inside own container")
        if let id = added {
            store.setPosition(id: id, position: .right)
            store.setCustomLabels(id: id, labels: PositionLabels(left: "Local", right: "Relu"))
        }
        let saved = store.state
        let reloaded = ProjectStore()
        check(reloaded.state == saved && reloaded.persistenceError == nil, "sandbox reload preserves complete updated state")
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: store.dataURL.path)
            let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue
            check(mode == 0o600, "saved state file permissions are exactly 0600")
        } catch {
            check(false, "saved state file permissions are readable")
        }

        do {
            _ = try Data(contentsOf: readCanary)
            check(false, "sandbox denies reading unrelated external canary")
        } catch {
            check(isPermissionDenial(error), "sandbox denies reading unrelated external canary")
        }

        let externalFD = Darwin.open(writeCanary, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        let writeErrno = errno
        if externalFD >= 0 { Darwin.close(externalFD) }
        check(externalFD == -1 && (writeErrno == EPERM || writeErrno == EACCES),
              "sandbox denies writing unrelated external canary")
        checkLoopbackDenial()

        print("RESULT \(failures) failure(s)")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    private static func isPermissionDenial(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(EPERM) || nsError.code == Int(EACCES)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionDenial(underlying)
        }
        return nsError.domain == NSCocoaErrorDomain &&
            (nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError)
    }

    private static func checkLoopbackDenial() {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            check(errno == EPERM || errno == EACCES, "sandbox denies loopback networking at socket creation")
            return
        }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(9).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let connectionErrno = errno
        // ECONNREFUSED fails this test: the connection must be prohibited, not merely refused by a port.
        check(result == -1 && (connectionErrno == EPERM || connectionErrno == EACCES),
              "sandbox denies loopback connect with EPERM or EACCES")
    }
}
