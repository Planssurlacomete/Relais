// swift-tools-version: 5.9
import PackageDescription

// The .app bundle is produced by Scripts/build.sh or Relais.xcodeproj.
let package = Package(
    name: "Relais",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Relais", targets: ["Relais"])],
    targets: [
        .executableTarget(
            name: "Relais",
            path: "Relais",
            exclude: ["Info.plist"],
            resources: [.copy("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
