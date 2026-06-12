// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ToolQualification",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ToolQualification", targets: ["ToolQualification"]),
    ],
    dependencies: [
        .package(path: "../XcircuitePackage"),
    ],
    targets: [
        .target(
            name: "ToolQualification",
            dependencies: [
                .product(name: "XcircuitePackage", package: "XcircuitePackage"),
            ]
        ),
        .testTarget(name: "ToolQualificationTests", dependencies: ["ToolQualification"]),
    ]
)
