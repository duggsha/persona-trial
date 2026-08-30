// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonaDesign",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "PersonaDesign", targets: ["PersonaDesign"])
    ],
    dependencies: [
        .package(path: "../PersonaCore")
    ],
    targets: [
        .target(
            name: "PersonaDesign",
            dependencies: ["PersonaCore"],
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageModes: [.v6]
)
