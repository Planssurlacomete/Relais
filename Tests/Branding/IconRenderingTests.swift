import AppKit

/// Native rendering checks only: no visible windows, data store or production app.
@main
struct IconRenderingTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description)
            checks += 1
        }
        func render(size: CGSize, scale: Int, drawing: () -> Void) -> NSBitmapImageRep {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            drawing()
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        func alphaBounds(_ bitmap: NSBitmapImageRep) -> CGRect? {
            var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        let template = RelaisIcon.templateImage(size: 18)
        check(template.isTemplate, "Menu-bar image is a native monochrome template")
        check(template.size == CGSize(width: 18, height: 18), "Menu-bar size is 18 logical points")
        check(!RelaisIcon.symbolImage(size: 18).isTemplate, "Panel symbol retains its app colors")
        check(RelaisIcon.templateImage(size: .nan).size == CGSize(width: 18, height: 18), "Invalid size has a safe native default")
        let fitted = RelaisIcon.fittedSymbolRect(in: CGRect(x: 0, y: 0, width: 40, height: 80))
        check(abs(fitted.width / fitted.height - RelaisIcon.symbolBounds.width / RelaisIcon.symbolBounds.height) < 0.0001,
              "A non-square destination never stretches the symbol")
        check(RelaisIcon.rail.intersects(RelaisIcon.lever), "Reference silhouette keeps its connected rail and lever")
        var renderedBounds: [CGRect] = []
        for scale in [1, 2] {
            let bitmap = render(size: template.size, scale: scale) {
                template.draw(in: CGRect(origin: .zero, size: template.size))
            }
            check(bitmap.pixelsWide == 18 * scale && bitmap.pixelsHigh == 18 * scale,
                  "Template renders at native 1x and Retina 2x dimensions")
            let bounds = alphaBounds(bitmap)!
            renderedBounds.append(CGRect(x: bounds.minX / CGFloat(scale), y: bounds.minY / CGFloat(scale),
                                         width: bounds.width / CGFloat(scale), height: bounds.height / CGFloat(scale)))
            check(bounds.minX > 0 && bounds.maxX < CGFloat(bitmap.pixelsWide), "Template preserves transparent horizontal padding")
            check(bounds.minY > 0 && bounds.maxY < CGFloat(bitmap.pixelsHigh), "Template preserves transparent vertical padding")
            let pixels = (0..<bitmap.pixelsHigh).flatMap { y in
                (0..<bitmap.pixelsWide).compactMap { x -> NSColor? in
                    guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { return nil }
                    return color.usingColorSpace(.deviceRGB)
                }
            }
            check(!pixels.isEmpty && pixels.allSatisfy { $0.redComponent < 0.02 && $0.greenComponent < 0.02 && $0.blueComponent < 0.02 },
                  "Template contains one black silhouette with transparency")
        }
        check(abs(renderedBounds[0].width - renderedBounds[1].width) <= 1 &&
              abs(renderedBounds[0].height - renderedBounds[1].height) <= 1,
              "Backing scale preserves the logical silhouette")

        // Native NSImageView performs the system template tint for each appearance.
        func nativeTemplate(_ appearance: NSAppearance) -> NSBitmapImageRep {
            let view = NSImageView(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
            view.image = template
            view.imageScaling = .scaleNone
            view.contentTintColor = .labelColor
            view.appearance = appearance
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            appearance.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: view.bounds, to: bitmap)
            }
            return bitmap
        }
        let light = nativeTemplate(NSAppearance(named: .aqua)!)
        let dark = nativeTemplate(NSAppearance(named: .darkAqua)!)
        check(alphaBounds(light) != nil, "Aqua template is visible in native image view")
        check(alphaBounds(dark) != nil, "Dark Aqua template is visible in native image view")
        func averageBrightness(_ bitmap: NSBitmapImageRep) -> CGFloat {
            var sum: CGFloat = 0, count: CGFloat = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 else { continue }
                    sum += (c.redComponent + c.greenComponent + c.blueComponent) / 3; count += 1
                }
            }
            return sum / max(count, 1)
        }
        check(averageBrightness(light) < 0.25 && averageBrightness(dark) > 0.75,
              "Native template tint contrasts correctly with light and dark appearance")

        if CommandLine.arguments.count == 2 {
            let canvas = CGSize(width: 620, height: 250)
            let preview = render(size: canvas, scale: 2) {
                for (column, name) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
                    let appearance = NSAppearance(named: name)!
                    let origin = CGFloat(column) * 310
                    appearance.performAsCurrentDrawingAppearance {
                        NSColor.windowBackgroundColor.setFill()
                        CGRect(x: origin, y: 0, width: 310, height: 250).fill()
                        let text: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor]
                        let caption: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
                        (column == 0 ? "Clair · Aqua" : "Sombre · Dark Aqua" as NSString)
                            .draw(at: CGPoint(x: origin + 24, y: 216), withAttributes: text)
                        RelaisIcon.drawApplicationIcon(in: CGRect(x: origin + 18, y: 76, width: 112, height: 112))
                        ("Application" as NSString).draw(at: CGPoint(x: origin + 42, y: 58), withAttributes: caption)
                        RelaisIcon.symbolImage(size: 32).draw(in: CGRect(x: origin + 167, y: 140, width: 32, height: 32))
                        ("Panneau / pastille" as NSString).draw(at: CGPoint(x: origin + 143, y: 120), withAttributes: caption)
                        // Draw the same template paths directly into the Retina preview,
                        // using AppKit's current native label tint instead of upscaling a 1x cache.
                        RelaisIcon.drawSymbol(in: CGRect(x: origin + 175, y: 81, width: 16, height: 16),
                                              railColor: .labelColor, leverColor: .labelColor)
                        ("Barre de menus · 18 pt" as NSString).draw(at: CGPoint(x: origin + 132, y: 58), withAttributes: caption)
                        ("Géométrie commune · rendu Retina ×2" as NSString)
                            .draw(at: CGPoint(x: origin + 24, y: 20), withAttributes: caption)
                    }
                }
            }
            try preview.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("PASS: \(checks) shared icon geometry, native Aqua/Dark Aqua template and Retina rendering assertions.")
    }
}
