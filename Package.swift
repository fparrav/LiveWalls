// swift-tools-version: 5.7
// Package.swift para compatibilidad con VS Code Swift Language Server

import PackageDescription

let package = Package(
    name: "LiveWalls",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "LiveWalls",
            targets: ["LiveWalls"]
        ),
    ],
    dependencies: [
        // Add package dependencies here
    ],
    targets: [
        .executableTarget(
            name: "LiveWalls",
            dependencies: [],
            path: "LiveWalls",
            exclude: [
                "Info.plist",
                "LiveWalls.entitlements",
                "Preview Content"
            ],
            sources: [
                ".",
            ]
        ),
    ]
)
