// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OmniMemo",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "omnimem", targets: ["omnimem"]),
    .library(name: "OmniMemoCore", targets: ["OmniMemoCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/orlandos-nl/MongoKitten.git", from: "7.9.0"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
  ],
  targets: [
    .target(
      name: "OmniMemoCore",
      dependencies: [
        .product(name: "MongoKitten", package: "MongoKitten"),
        .product(name: "MCP", package: "swift-sdk"),
      ],
      resources: [.copy("Skills"), .copy("REA")]),
    .executableTarget(
      name: "omnimem",
      dependencies: [
        "OmniMemoCore", .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]),
    .testTarget(name: "OmniMemoCoreTests", dependencies: ["OmniMemoCore"]),
  ],
  swiftLanguageModes: [.v5]
)
