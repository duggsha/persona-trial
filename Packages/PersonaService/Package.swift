// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonaService",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "PersonaService", targets: ["PersonaService"])
    ],
    // No third-party dependencies: the wrist band's BLE/OTA client (Nordic's
    // McuMgr) went with the hardware support this trial doesn't include.
    dependencies: [
        .package(path: "../PersonaCore")
    ],
    targets: [
        .target(
            name: "PersonaService",
            dependencies: ["PersonaCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
