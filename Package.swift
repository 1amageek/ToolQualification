// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let circuiteFoundationDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(
        url: "https://github.com/1amageek/CircuiteFoundation.git",
        revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac"
    )

let package = Package(
    name: "ToolQualification",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ToolQualification", targets: ["ToolQualification"]),
        .library(name: "ToolQualificationCLICore", targets: ["ToolQualificationCLICore"]),
        .executable(name: "toolqualification", targets: ["ToolQualificationCLI"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
    ],
    targets: [
        .target(
            name: "ToolQualification",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(
            name: "ToolQualificationCLICore",
            dependencies: [
                "ToolQualification",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .executableTarget(
            name: "ToolQualificationCLI",
            dependencies: ["ToolQualificationCLICore"]
        ),
        .testTarget(
            name: "ToolQualificationTests",
            dependencies: [
                "ToolQualification",
            ]
        ),
        .testTarget(
            name: "ToolQualificationCLICoreTests",
            dependencies: [
                "ToolQualificationCLICore",
                "ToolQualification",
            ]
        ),
    ]
)
