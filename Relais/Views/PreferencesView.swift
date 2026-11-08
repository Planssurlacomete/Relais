import SwiftUI

private typealias PreferencesState<Value> = SwiftUI.State<Value>

struct PreferencesView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var login: LoginItemController
    @PreferencesState<String> private var left = ""
    @PreferencesState<String> private var right = ""
    @PreferencesState<Bool> private var initialized = false

    private var hasEmptyLabel: Bool {
        left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Réglages de Relais").font(.system(size: 20, weight: .semibold))
                Text("Un projet, deux positions.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Noms globaux").font(.system(size: 13, weight: .semibold))
                LabeledContent("À gauche") {
                    TextField("Position gauche", text: $left)
                        .accessibilityLabel("Nom global de la position gauche")
                        .accessibilityIdentifier("global-left-label")
                }
                LabeledContent("À droite") {
                    TextField("Position droite", text: $right)
                        .accessibilityLabel("Nom global de la position droite")
                        .accessibilityIdentifier("global-right-label")
                }
                Text(hasEmptyLabel ? "Chaque position doit conserver un nom. Le dernier nom valide reste enregistré." : "Les projets sans personnalisation suivent ces noms automatiquement. Les changements sont enregistrés au fil de la saisie.")
                    .font(.system(size: 11))
                    .foregroundStyle(hasEmptyLabel ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Lancer Relais à l’ouverture de session", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .accessibilityIdentifier("launch-at-login")
                Text(login.statusDescription)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if login.requiresApproval {
                    Button("Annuler la demande de lancement") { login.setEnabled(false) }
                        .font(.system(size: 11))
                }
                if let message = login.errorMessage {
                    Text(message).font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Ouvrir les éléments d’ouverture de macOS…") { login.openSystemSettings() }
                    .font(.system(size: 11))
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Vos données restent sur ce Mac.").font(.system(size: 11, weight: .medium))
                Text("Clic droit sur un projet pour le renommer, personnaliser ses positions ou le supprimer.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Interrupteur adapté de Saiyed-Tanvir · licence MIT", destination: URL(string: "https://uiverse.io/Saiyed-Tanvir/pretty-moose-9")!)
                    .font(.system(size: 10))
            }
            if let error = store.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 390)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.dark)
        .onAppear {
            left = store.state.globalLabels.left
            right = store.state.globalLabels.right
            initialized = true
            login.refresh()
        }
        .onChange(of: left) { _, _ in persistLabels() }
        .onChange(of: right) { _, _ in persistLabels() }
    }

    private func persistLabels() {
        guard initialized else { return }
        let validLeft = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let validRight = right.trimmingCharacters(in: .whitespacesAndNewlines)
        store.setGlobalLabels(PositionLabels(
            left: validLeft.isEmpty ? store.state.globalLabels.left : left,
            right: validRight.isEmpty ? store.state.globalLabels.right : right
        ))
    }
}
