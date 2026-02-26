// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthClaw",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "HealthClaw", targets: ["HealthClaw"]),
    ],
    targets: [
        .target(
            name: "HealthClaw",
            path: "HealthClaw"
        ),
    ]
)
