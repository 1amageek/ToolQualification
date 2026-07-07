// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ToolQualification",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ToolQualification", targets: ["ToolQualification"]),
        .library(name: "ToolQualificationCLICore", targets: ["ToolQualificationCLICore"]),
        .executable(name: "toolqualification", targets: ["ToolQualificationCLI"]),
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
        .target(
            name: "ToolQualificationCLICore",
            dependencies: ["ToolQualification"]
        ),
        .executableTarget(
            name: "ToolQualificationCLI",
            dependencies: ["ToolQualificationCLICore"]
        ),
        .testTarget(name: "ToolQualificationTests", dependencies: ["ToolQualification"]),
        .testTarget(
            name: "ToolQualificationCLICoreTests",
            dependencies: ["ToolQualificationCLICore", "ToolQualification"]
        ),
    ]
)
