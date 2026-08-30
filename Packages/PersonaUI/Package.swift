// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonaUI",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "PersonaUI", targets: ["PersonaUI"])
    ],
    // No third-party dependencies: the trial renders Home from local packages
    // only, so it builds and runs with the network off.
    dependencies: [
        .package(path: "../PersonaCore"),
        .package(path: "../PersonaService"),
        .package(path: "../PersonaDesign")
    ],
    targets: [
        .target(
            name: "PersonaUI",
            dependencies: ["PersonaCore", "PersonaService", "PersonaDesign"],
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageModes: [.v6]
)
