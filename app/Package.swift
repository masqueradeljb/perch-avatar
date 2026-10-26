// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Perch", targets: ["AvatarApp"])],
    targets: [
        .target(name: "AvatarCore"),
        .executableTarget(name: "AvatarApp", dependencies: ["AvatarCore"]),
        .testTarget(name: "AvatarCoreTests", dependencies: ["AvatarCore"]),
    ]
)
