// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TaskSnap",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaskSnap", targets: ["TaskSnap"])
    ],
    targets: [
        .executableTarget(
            name: "TaskSnap",
            path: "Sources"
        ),
        .testTarget(
            name: "TaskSnapTests",
            dependencies: ["TaskSnap"],
            path: "Tests"
        )
    ]
)
