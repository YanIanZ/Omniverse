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
    // 0.x minors may break the API: stay on the resolved minor until upgraded on purpose.
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.1")),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
    .package(url: "https://github.com/swift-server/RediStack.git", from: "1.6.0"),
  ],
  targets: [
    .target(
      name: "OmniMemoCore",
      dependencies: [
        .product(name: "MongoKitten", package: "MongoKitten"),
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "RediStack", package: "RediStack"),
      ],
      resources: [.copy("Skills"), .copy("REA")]),
    // Vapor 4 HTTP/WebSocket server for Mission Control; shares the core domain layer.
    .target(
      name: "OmniServer",
      dependencies: ["OmniMemoCore", .product(name: "Vapor", package: "vapor")]),
    .executableTarget(
      name: "omnimem",
      dependencies: [
        "OmniMemoCore", "OmniServer", .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]),
    .testTarget(
      name: "OmniMemoCoreTests",
      dependencies: ["OmniMemoCore", "OmniServer", .product(name: "XCTVapor", package: "vapor")]),
  ],
  swiftLanguageModes: [.v5]
)
