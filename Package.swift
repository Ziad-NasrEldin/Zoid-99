// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Zoid99",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Zoid99", targets: ["Zoid99"])],
    targets: [
        .executableTarget(
            name: "Zoid99",
            path: "Sources/Zoid99",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "Zoid99Tests",
            dependencies: ["Zoid99"],
            path: "Tests/Zoid99Tests",
            resources: [.process("Fixtures")]
        )
    ]
)
