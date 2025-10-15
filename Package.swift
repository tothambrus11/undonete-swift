// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Undonete",
    platforms: [
        .macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Undonete",
            targets: ["Undonete"]
        ),
        .library(
            name: "VectorEditorCore",
            targets: ["VectorEditorCore"]
        ),
        .executable(
            name: "VectorEditorSDLApp",
            targets: ["VectorEditorSDLApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ctreffs/SwiftSDL2.git", from: "1.4.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Undonete"
        ),
        .target(
            name: "VectorEditorCore",
            dependencies: ["Undonete"]
        ),
        .executableTarget(
            name: "VectorEditorSDLApp",
            dependencies: [
                "VectorEditorCore",
                .product(name: "SDL", package: "SwiftSDL2")
            ]
        ),
        .testTarget(
            name: "UndoneteTests",
            dependencies: ["Undonete"]
        ),
        .testTarget(
            name: "VectorEditorCoreTests",
            dependencies: ["VectorEditorCore", "Undonete"]
        ),
    ]
)
