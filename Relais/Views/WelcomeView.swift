import SwiftUI

/// The draft is kept separate from persistent state until the atomic save succeeds.
@MainActor
final class WelcomeForm: ObservableObject {
    @Published var left = ""
    @Published var right = ""
    @Published private(set) var saveError: String?

    var labels: PositionLabels { PositionLabels(left: left, right: right) }
    var canSubmit: Bool { labels.isValidForInitialSetup }

    @discardableResult
    func submit(to store: ProjectStore) -> Bool {
        guard canSubmit else { return false }
        guard store.completeInitialSetup(labels: labels) else {
            saveError = store.persistenceError ?? "La configuration n’a pas pu être enregistrée. Vous pouvez réessayer."
            return false
        }
        saveError = nil
        return true
    }
}

struct WelcomeView: View {
    @ObservedObject var store: ProjectStore
    var onComplete: () -> Void
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    @StateObject private var form = WelcomeForm()
    @FocusState private var focusedField: Field?
    private enum Field { case left, right }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Bienvenue sur Relais")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(white: 0.91))
                Text("Choisissez les noms des deux côtés de votre interrupteur. Vous pourrez les modifier plus tard.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Position gauche").font(.system(size: 11)).foregroundStyle(Color(white: 0.73))
                    TextField("Premier intervenant", text: $form.left)
                        .focused($focusedField, equals: .left)
                        .accessibilityLabel("Position gauche")
                        .accessibilityIdentifier("setup-left-label")
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Position droite").font(.system(size: 11)).foregroundStyle(Color(white: 0.73))
                    TextField("Second intervenant", text: $form.right)
                        .focused($focusedField, equals: .right)
                        .accessibilityLabel("Position droite")
                        .accessibilityIdentifier("setup-right-label")
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            if let error = form.saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setup-save-error")
            }
            HStack {
                Spacer(minLength: 0)
                Button("Commencer", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canSubmit)
                    .accessibilityIdentifier("complete-initial-setup")
            }
        }
        .padding(22)
        .frame(width: 328)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: WelcomeHeightPreference.self, value: geometry.size.height)
            }
        }
        .background(Color(red: 0.065, green: 0.069, blue: 0.078))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .preferredColorScheme(.dark)
        .onSubmit(commit)
        // Escape never clears the draft or skips configuration.
        .onExitCommand {}
        .onAppear { focusedField = .left }
        .onPreferenceChange(WelcomeHeightPreference.self) { height in
            guard height.isFinite, height > 0 else { return }
            onContentHeightChange(height)
        }
    }

    private func commit() {
        guard form.submit(to: store) else { return }
        onComplete()
    }
}

private struct WelcomeHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
