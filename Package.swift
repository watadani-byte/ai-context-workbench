// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIContextWorkbench",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AIContextWorkbenchApp", targets: ["AIContextWorkbenchApp"]),
        .library(name: "WorkbenchCore", targets: ["WorkbenchCore"])
    ],
    targets: [
        .target(name: "WorkbenchCore"),
        .executableTarget(
            name: "AIContextWorkbenchApp",
            dependencies: ["WorkbenchCore"]
        ),
        .testTarget(
            name: "WorkbenchCoreTests",
            dependencies: ["WorkbenchCore"]
        )
    ]
)
