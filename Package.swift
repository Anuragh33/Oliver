// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Oliver",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Oliver", targets: ["Oliver"])
    ],
    targets: [
        .executableTarget(
            name: "Oliver",
            path: "Sources/Oliver",
            exclude: ["Info.plist", "Oliver.entitlements"],
            resources: [
                .process("Assets")
            ]
        )
    ]
)