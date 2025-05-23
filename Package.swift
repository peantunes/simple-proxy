// swift-tools-version: 5.8
// Package.swift
// Swift Package Manager file
import PackageDescription

let package = Package(
    name: "SimpleProxy",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.82.0")
    ],
    targets: [
        .target(
            name: "SimpleProxy",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        )
    ]
)

