// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftDataPager",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .tvOS(.v17),
        .visionOS(.v1),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "SwiftDataPager",
            targets: ["SwiftDataPager"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/markbattistella/SimpleLogger", from: "26.0.0")
    ],
    targets: [
        .target(
            name: "SwiftDataPager",
            dependencies: ["SimpleLogger"]
        ),
        .testTarget(
            name: "SwiftDataPagerTests",
            dependencies: ["SwiftDataPager"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
