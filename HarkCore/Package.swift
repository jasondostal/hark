// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HarkCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HarkCore", targets: ["HarkCore"])],
    targets: [
        .target(name: "HarkCore"),
        .testTarget(name: "HarkCoreTests", dependencies: ["HarkCore"],
                    resources: [.copy("Fixtures")]),
    ]
)
