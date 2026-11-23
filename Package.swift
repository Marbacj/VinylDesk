// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VinylDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VinylDesk", targets: ["VinylDesk"])
    ],
    targets: [
        .executableTarget(
            name: "VinylDesk",
            path: "Sources/VinylDesk",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "VinylDeskTests",
            dependencies: ["VinylDesk"],
            path: "Tests/VinylDeskTests"
        )
    ]
)
