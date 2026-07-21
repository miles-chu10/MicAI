// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MicAI",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(
      url: "https://github.com/FluidInference/FluidAudio",
      exact: "0.15.5"
    )
  ]
)
