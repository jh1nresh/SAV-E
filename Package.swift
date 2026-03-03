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
        // .package(url: "https://github.com/privy-io/privy-ios.git", from: "1.0.0"),

        // Supabase Swift SDK for backend
        // .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "Wanderly",
            dependencies: [
                // "PrivySDK",
                // .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Wanderly"
        ),
    ]
)
