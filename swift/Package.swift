// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TurboToken",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "TurboToken", targets: ["TurboToken"]),
    ],
    targets: [
        .systemLibrary(
            name: "CTurboToken",
            pkgConfig: nil,
            providers: []
        ),
        .target(
            name: "TurboToken",
            dependencies: ["CTurboToken"]
        ),
        .testTarget(
            name: "TurboTokenTests",
            dependencies: ["TurboToken"]
        ),
    ]
)
