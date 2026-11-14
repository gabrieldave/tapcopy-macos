// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TapCopy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TapCopy", targets: ["TapCopy"])
    ],
    targets: [
        .executableTarget(
            name: "TapCopy",
            path: "Sources/TapCopy",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
