import SwiftUI

/// The same rail-and-lever mark as AppIcon and the menu-bar template.
struct RelaisIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: RelaisIcon.symbolImage(size: size))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
