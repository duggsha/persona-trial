// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonaCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "PersonaCore", targets: ["PersonaCore"])
    ],
    targets: [
        .target(name: "PersonaCore")
    ],
    swiftLanguageModes: [.v6]
)
