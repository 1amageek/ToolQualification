// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(
        url: "https://github.com/1amageek/CircuiteFoundation.git",
        revision: "7abcac83517935c9b9f7553d7016d62cffde259d"
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
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
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
