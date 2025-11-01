// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LocalDeps",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "LocalDeps", targets: ["LocalDeps"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/mattt/AnyLanguageModel.git",
      from: "0.2.2",
      // Enable the backends you want:
      traits: ["MLX"] // or ["CoreML"], ["Llama"], or multiple
    )
  ],
  targets: [
    .target(
      name: "LocalDeps",
      dependencies: [
        .product(name: "AnyLanguageModel", package: "AnyLanguageModel")
      ]
    ),
  ]
)
