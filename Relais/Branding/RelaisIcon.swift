import AppKit

/// One native vector silhouette for the app tile, floating panels and menu bar.
/// Coordinates preserve the original Relais app icon: a rail and a right-hand lever.
enum RelaisIcon {
    static let canvasSize: CGFloat = 1024
    static let rail = CGRect(x: 228, y: 466, width: 568, height: 92)
    static let lever = CGRect(x: 610, y: 316, width: 132, height: 392)
    static var symbolBounds: CGRect { rail.union(lever) }

    static var railColor: NSColor {
        NSColor(calibratedRed: 0.129, green: 0.588, blue: 0.953, alpha: 1)
    }

    /// Resolution-independent drawing: AppKit rasterizes at the screen's backing scale.
    static func templateImage(size: CGFloat = 18) -> NSImage {
        symbolImage(size: size, monochrome: true)
    }

    static func symbolImage(size: CGFloat) -> NSImage {
        symbolImage(size: size, monochrome: false)
    }

    private static func symbolImage(size: CGFloat, monochrome: Bool) -> NSImage {
        let dimension = size.isFinite && size > 0 ? size : 18
        let image = NSImage(size: NSSize(width: dimension, height: dimension), flipped: false) { rect in
            let inset = rect.width / 18
            drawSymbol(in: rect.insetBy(dx: inset, dy: inset),
                       railColor: monochrome ? .black : railColor,
                       leverColor: monochrome ? .black : .labelColor)
            return true
        }
        image.isTemplate = monochrome
        image.accessibilityDescription = "Relais"
        return image
    }

    /// Fits the unchanging symbol into any bounds without stretching it.
    static func fittedSymbolRect(in rect: CGRect) -> CGRect {
        let bounds = symbolBounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func drawSymbol(in rect: CGRect, railColor: NSColor, leverColor: NSColor,
                           shadow: Bool = false) {
        guard rect.width > 0, rect.height > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let fitted = fittedSymbolRect(in: rect)
        let scale = fitted.width / symbolBounds.width
        context.saveGState()
        context.translateBy(x: fitted.minX, y: fitted.minY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -symbolBounds.minX, y: -symbolBounds.minY)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        railColor.setFill()
        NSBezierPath(roundedRect: rail, xRadius: rail.height / 2, yRadius: rail.height / 2).fill()
        NSGraphicsContext.saveGraphicsState()
        if shadow {
            let shading = NSShadow()
            shading.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shading.shadowBlurRadius = 28
            shading.shadowOffset = NSSize(width: 0, height: -4)
            shading.set()
        }
        leverColor.setFill()
        NSBezierPath(roundedRect: lever, xRadius: lever.width / 2, yRadius: lever.width / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    /// App tile uses exactly the same rail/lever paths as the smaller symbols.
    static func drawApplicationIcon(in rect: CGRect) {
        guard rect.width > 0, rect.height > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let side = min(rect.width, rect.height)
        context.saveGState()
        context.translateBy(x: rect.midX - side / 2, y: rect.midY - side / 2)
        context.scaleBy(x: side / canvasSize, y: side / canvasSize)
        let tile = NSBezierPath(roundedRect: CGRect(x: 68, y: 68, width: 888, height: 888),
                                xRadius: 196, yRadius: 196)
        NSGradient(starting: NSColor(calibratedWhite: 0.16, alpha: 1),
                   ending: NSColor(calibratedWhite: 0.055, alpha: 1))!
            .draw(in: tile, angle: -90)
        NSColor(white: 1, alpha: 0.08).setStroke()
        tile.lineWidth = 3
        tile.stroke()
        drawSymbol(in: symbolBounds, railColor: railColor, leverColor: .white, shadow: true)
        context.restoreGState()
    }
}
