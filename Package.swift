// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-composable-architecture-firebase",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ComposableArchitectureFirebase",
            targets: ["ComposableArchitectureFirebase"]),
        .library(
            name: "FirebaseStorageLive",
            targets: ["FirebaseStorageLive"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            .upToNextMajor(from: "1.11.2")
        ),
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            .upToNextMajor(from: "10.28.1")
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ComposableArchitectureFirebase",
            dependencies: [
                .product(
                    name: "ComposableArchitecture",
                    package: "swift-composable-architecture"
                )
            ]
        ),
        .target(
            name: "FirebaseStorageLive",
            dependencies: [
                "ComposableArchitectureFirebase",
                .product(
                    name: "ComposableArchitecture",
                    package: "swift-composable-architecture"
                ),
                .product(
                    name: "FirebaseFirestore",
                    package: "firebase-ios-sdk"
                ),
                .product(
                    name: "FirebaseDatabase",
                    package: "firebase-ios-sdk"
                ),
            ]
        ),

        .testTarget(
            name: "ComposableArchitectureFirebaseTests",
            dependencies: ["ComposableArchitectureFirebase"]),
    ]
)
