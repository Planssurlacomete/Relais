import SwiftUI

/// Native adaptation of “pretty-moose-9” by Saiyed-Tanvir (Uiverse, MIT).
/// The original proportions are retained; the lever only slides, as requested.
struct MechanicalSwitch: View {
    @Binding var position: RelayPosition
    let leftLabel: String
    let rightLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    private let unit: CGFloat = 12
    private var isRight: Bool { position == .right }

    var body: some View {
        Button {
            setPosition(isRight ? .left : .right)
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isRight ? Color(red: 0.129, green: 0.588, blue: 0.953) : Color(white: 0.8))
                    .frame(width: 5 * unit, height: unit)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 1.4 * unit, height: 3.4 * unit)
                    .shadow(color: .black.opacity(0.6), radius: 2.5, x: 0, y: 0)
                    .offset(x: (0.3 + (isRight ? 2.5 : 0)) * unit)
            }
            .frame(width: 5 * unit, height: 44)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 1.5)
                        .padding(-3)
                }
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            setPosition(.left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            setPosition(.right)
            return .handled
        }
        .accessibilityLabel("Passer le relais")
        .accessibilityValue(isRight ? rightLabel : leftLabel)
        .accessibilityHint("Espace pour basculer. Flèches gauche et droite pour choisir une position.")
        .help("\(leftLabel) ↔ \(rightLabel)")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: position)
    }

    private func setPosition(_ newPosition: RelayPosition) {
        position = newPosition
    }
}
