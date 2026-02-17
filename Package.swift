// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Litebar",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Litebar", targets: ["Litebar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1"),
    ],
    targets: [
        .executableTarget(
            name: "Litebar",
            dependencies: ["Yams"],
            path: "Sources"
        ),
    ]
)
