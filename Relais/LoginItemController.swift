import AppKit
import Combine
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var statusDescription = ""
    @Published private(set) var errorMessage: String?

    init() { refresh() }

    /// ServiceManagement is the source of truth; no cached UserDefaults flag.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
        switch status {
        case .enabled: statusDescription = "Relais sera ouvert à la prochaine connexion."
        case .notRegistered: statusDescription = "Le lancement automatique est désactivé."
        case .requiresApproval:
            statusDescription = "Autorisation requise dans Réglages Système › Ouverture."
        case .notFound:
            statusDescription = "Installez Relais dans Applications pour configurer le lancement."
        @unknown default: statusDescription = "État système indisponible."
        }
    }

    func setEnabled(_ enabled: Bool) {
#if RELAIS_TESTING
        // Test identities must never register or remove a real macOS login item.
        errorMessage = "Le lancement automatique n’est pas modifié par l’application de test."
        return
#else
        errorMessage = nil
        do {
            if enabled {
                if SMAppService.mainApp.status == .requiresApproval {
                    // Already registered: a second registration cannot grant consent.
                    SMAppService.openSystemSettingsLoginItems()
                } else if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "macOS n’a pas pu modifier ce réglage : \(error.localizedDescription)"
        }
        refresh()
#endif
    }

    func openSystemSettings() {
#if RELAIS_TESTING
        errorMessage = "Les réglages système ne sont pas ouverts par l’application de test."
#else
        SMAppService.openSystemSettingsLoginItems()
#endif
    }
}
