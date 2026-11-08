import AppKit
import Foundation

// App and menu symbols share the reference geometry in Relais/Branding/RelaisIcon.swift.
@main
enum GenerateIcon {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "RelaisIcon", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected an iconset output directory."])
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        func png(pixels: Int) throws -> Data {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            RelaisIcon.drawApplicationIcon(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])!
        }

        for logical in [16, 32, 128, 256, 512] {
            for density in [1, 2] {
                let suffix = density == 2 ? "@2x" : ""
                let name = "icon_\(logical)x\(logical)\(suffix).png"
                try png(pixels: logical * density).write(to: output.appendingPathComponent(name))
            }
        }
        print("Generated native icon: \(output.path)")

        // ICNS accepts PNG payloads in these native size/scale chunks. Writing the
        // container here also works on command-line-only installations of macOS.
        func be32(_ value: Int) -> Data {
            var integer = UInt32(value).bigEndian
            return withUnsafeBytes(of: &integer) { Data($0) }
        }
        let chunks: [(String, String)] = [
            ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
            ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
            ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
            ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
            ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
            ("ic14", "icon_256x256@2x.png")
        ]
        var body = Data()
        for (type, file) in chunks {
            let payload = try Data(contentsOf: output.appendingPathComponent(file))
            body.append(Data(type.utf8))
            body.append(be32(payload.count + 8))
            body.append(payload)
        }
        var icon = Data("icns".utf8)
        icon.append(be32(body.count + 8))
        icon.append(body)
        let iconURL = output.deletingLastPathComponent().appendingPathComponent("AppIcon.icns")
        try icon.write(to: iconURL, options: .atomic)
        print("Generated ICNS: \(iconURL.path)")
    }
}
