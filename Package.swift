// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Logbook",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(name: "Logbook", targets: ["Logbook"])
    ],
    targets: [
        .target(
            name: "Logbook"
        ),
        .testTarget(
            name: "LogbookTests",
            dependencies: ["Logbook"]
        ),
    ]
)
