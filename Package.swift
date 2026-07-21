// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MicAI",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "MicAICore", targets: ["MicAICore"]),
    .executable(name: "MicAI", targets: ["MicAI"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/FluidInference/FluidAudio",
      exact: "0.15.5"
    )
  ],
  targets: [
    .target(
      name: "MicAICore",
      dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio")
      ]
    ),
    .executableTarget(
      name: "MicAI",
      dependencies: ["MicAICore"]
    ),
    .testTarget(
      name: "MicAICoreTests",
      dependencies: ["MicAICore"]
    ),
  ]
)
