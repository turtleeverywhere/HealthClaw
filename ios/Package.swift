// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthBridge",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "HealthBridge", targets: ["HealthBridge"]),
    ],
    targets: [
        .target(
            name: "HealthBridge",
            path: "HealthBridge"
        ),
    ]
)
