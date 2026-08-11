// swift-tools-version: 6.3
import PackageDescription

let circuiteFoundationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    exact: "26.812.0"
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
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            ]
        ),
        .target(
            name: "ToolQualificationCLICore",
            dependencies: [
                "ToolQualification",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(
                    name: "CircuiteFoundationFoundation",
                    package: "CircuiteFoundation"
                ),
                .product(
                    name: "CircuiteFoundationCrypto",
                    package: "CircuiteFoundation"
                ),
                .product(
                    name: "CircuiteFoundationFileSystem",
                    package: "CircuiteFoundation"
                ),
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
                .product(
                    name: "CircuiteFoundationFoundation",
                    package: "CircuiteFoundation"
                ),
                .product(
                    name: "CircuiteFoundationCrypto",
                    package: "CircuiteFoundation"
                ),
                .product(
                    name: "CircuiteFoundationFileSystem",
                    package: "CircuiteFoundation"
                ),
            ]
        ),
        .testTarget(
            name: "ToolQualificationCLICoreTests",
            dependencies: [
                "ToolQualificationCLICore",
                "ToolQualification",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(
                    name: "CircuiteFoundationFoundation",
                    package: "CircuiteFoundation"
                ),
                .product(
                    name: "CircuiteFoundationCrypto",
                    package: "CircuiteFoundation"
                ),
                .product(
                    name: "CircuiteFoundationFileSystem",
                    package: "CircuiteFoundation"
                ),
            ]
        ),
    ]
)
