// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wanderly",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Wanderly",
            targets: ["Wanderly"]
        ),
    ],
    dependencies: [
        // Privy iOS SDK for authentication
        .package(url: "https://github.com/privy-io/privy-ios.git", .upToNextMinor(from: "2.10.1")),
    ],
    targets: [
        .target(
            name: "Wanderly",
            dependencies: [
                .product(name: "Privy", package: "privy-ios"),
            ],
            path: "Wanderly"
        ),
    ]
)
