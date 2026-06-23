// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VirtualFaceCam",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VirtualFaceCamApp",
            targets: ["VirtualFaceCamApp"]
        ),
        .library(
            name: "VirtualFaceCamDALPluginScaffold",
            targets: ["VirtualFaceCamDALPluginScaffold"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VirtualFaceCamApp",
            path: "Sources/VirtualFaceCamApp",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "VirtualFaceCamDALPluginScaffold",
            path: "Sources/VirtualFaceCamDALPluginScaffold",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "VirtualFaceCamAppTests",
            dependencies: ["VirtualFaceCamApp"],
            path: "Tests/VirtualFaceCamAppTests"
        )
    ]
)
