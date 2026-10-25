// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Brim",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Brim", targets: ["Brim"]),
        .library(name: "BrimKit", targets: ["BrimKit"]),
    ],
    targets: [
        .target(
            name: "BrimKit",
            path: "Sources/BrimKit"
        ),
        .executableTarget(
            name: "Brim",
            dependencies: ["BrimKit"],
            path: "Sources/Brim"
        ),
        .testTarget(
            name: "BrimTests",
            dependencies: ["BrimKit"],
            path: "Tests/BrimTests"
        ),
    ]
)
