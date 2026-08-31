// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MicAI",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: [
    .library(name: "MicAICore", targets: ["MicAICore"]),
    .executable(name: "MicAI", targets: ["MicAI"]),
    .executable(name: "MicAIiOS", targets: ["MicAIiOS"]),
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
    .executableTarget(
      name: "MicAIiOS",
      dependencies: ["MicAICore"]
    ),
    .testTarget(
      name: "MicAICoreTests",
      dependencies: ["MicAICore"]
    ),
    .testTarget(
      name: "MicAIAppTests",
      dependencies: ["MicAI"]
    ),
  ]
)
