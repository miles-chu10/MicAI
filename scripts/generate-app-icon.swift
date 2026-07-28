#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("usage: generate-app-icon.swift <output.iconset>\n", stderr)
  exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
try? fileManager.removeItem(at: outputDirectory)
try fileManager.createDirectory(
  at: outputDirectory,
  withIntermediateDirectories: true
)

let variants: [(name: String, pixels: Int)] = [
  ("icon_16x16.png", 16),
  ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32),
  ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512),
  ("icon_512x512@2x.png", 1_024),
]

for variant in variants {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: variant.pixels,
      pixelsHigh: variant.pixels,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    throw CocoaError(.fileWriteUnknown)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  drawIcon(size: CGFloat(variant.pixels))
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  try png.write(to: outputDirectory.appendingPathComponent(variant.name))
}

func drawIcon(size: CGFloat) {
  let scale = size / 1_024
  let canvas = NSRect(x: 0, y: 0, width: size, height: size)
  NSColor.clear.setFill()
  canvas.fill()

  let tile = NSBezierPath(
    roundedRect: canvas.insetBy(dx: 36 * scale, dy: 36 * scale),
    xRadius: 218 * scale,
    yRadius: 218 * scale
  )
  tile.addClip()
  let background = NSGradient(
    colors: [
      NSColor(calibratedRed: 0.03, green: 0.10, blue: 0.20, alpha: 1),
      NSColor(calibratedRed: 0.02, green: 0.48, blue: 0.52, alpha: 1),
    ]
  )
  background?.draw(in: canvas, angle: 35)

  let glow = NSBezierPath(ovalIn: NSRect(
    x: 190 * scale,
    y: 285 * scale,
    width: 644 * scale,
    height: 644 * scale
  ))
  NSColor(calibratedRed: 0.25, green: 0.95, blue: 0.80, alpha: 0.18).setFill()
  glow.fill()

  let microphone = NSBezierPath(
    roundedRect: NSRect(
      x: 390 * scale,
      y: 344 * scale,
      width: 244 * scale,
      height: 390 * scale
    ),
    xRadius: 122 * scale,
    yRadius: 122 * scale
  )
  NSColor.white.setFill()
  microphone.fill()

  let cradle = NSBezierPath()
  cradle.move(to: NSPoint(x: 314 * scale, y: 522 * scale))
  cradle.curve(
    to: NSPoint(x: 710 * scale, y: 522 * scale),
    controlPoint1: NSPoint(x: 314 * scale, y: 255 * scale),
    controlPoint2: NSPoint(x: 710 * scale, y: 255 * scale)
  )
  cradle.lineWidth = 52 * scale
  cradle.lineCapStyle = .round
  NSColor.white.setStroke()
  cradle.stroke()

  let stem = NSBezierPath()
  stem.move(to: NSPoint(x: 512 * scale, y: 300 * scale))
  stem.line(to: NSPoint(x: 512 * scale, y: 215 * scale))
  stem.move(to: NSPoint(x: 402 * scale, y: 215 * scale))
  stem.line(to: NSPoint(x: 622 * scale, y: 215 * scale))
  stem.lineWidth = 52 * scale
  stem.lineCapStyle = .round
  stem.stroke()

  let waveColor = NSColor(calibratedRed: 0.60, green: 1.0, blue: 0.89, alpha: 0.95)
  waveColor.setStroke()
  for (x, height) in [(226.0, 100.0), (154.0, 54.0), (798.0, 100.0), (870.0, 54.0)] {
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: x * scale, y: (512 - height) * scale))
    wave.line(to: NSPoint(x: x * scale, y: (512 + height) * scale))
    wave.lineWidth = 32 * scale
    wave.lineCapStyle = .round
    wave.stroke()
  }

  let highlight = NSBezierPath(
    roundedRect: NSRect(
      x: 433 * scale,
      y: 584 * scale,
      width: 158 * scale,
      height: 92 * scale
    ),
    xRadius: 46 * scale,
    yRadius: 46 * scale
  )
  NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
  highlight.fill()
}
