#!/usr/bin/env swift

// Draws the 1024x1024 app icon.
//
// Run through `make icon` (or `swift tools/generate-app-icon.swift <path>`)
// after changing the colours below. The result is committed, so this script is
// only needed when the icon itself changes.
//
// App icons must be opaque: the bitmap is created without an alpha channel and
// iOS applies the rounded mask itself.

import AppKit
import CoreGraphics
import Foundation
import ImageIO

let side = 1024
let defaultOutput = "VdvMap/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultOutput

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fail("sRGB colour space is not available")
}

guard let context = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fail("could not create the drawing context")
}

let rect = CGRect(x: 0, y: 0, width: side, height: side)

// Background: deep blue in the south west, teal in the north east.
let backgroundColors = [
    CGColor(red: 0.05, green: 0.20, blue: 0.42, alpha: 1),
    CGColor(red: 0.04, green: 0.43, blue: 0.55, alpha: 1)
]
guard let background = CGGradient(
    colorsSpace: colorSpace,
    colors: backgroundColors as CFArray,
    locations: [0, 1]
) else {
    fail("could not create the background gradient")
}
context.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: side, y: side),
    options: []
)

// Foreground: a white bus glyph taken from SF Symbols.
//
// The symbol is configured with a white palette before drawing: an SF Symbol is
// black pixels inside an alpha shape, so drawing it straight into a grey mask
// context would composite to black and paint nothing.
func drawGlyph(named name: String, heightRatio: CGFloat) {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        fail("the SF Symbol \(name) is not available")
    }

    let glyphHeight = CGFloat(side) * heightRatio
    let configuration = NSImage.SymbolConfiguration(pointSize: glyphHeight, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let glyph = symbol.withSymbolConfiguration(configuration) else {
        fail("could not configure the SF Symbol \(name)")
    }

    let size = glyph.size
    let scale = glyphHeight / max(size.height, 1)
    let glyphRect = NSRect(
        x: (CGFloat(side) - size.width * scale) / 2,
        y: (CGFloat(side) - size.height * scale) / 2,
        width: size.width * scale,
        height: size.height * scale
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    glyph.draw(in: glyphRect)
    NSGraphicsContext.restoreGraphicsState()
}

drawGlyph(named: "bus.fill", heightRatio: 0.44)

guard let image = context.makeImage() else {
    fail("could not render the icon")
}

let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

guard
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.png" as CFString,
        1,
        nil
    )
else {
    fail("could not create \(outputPath)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fail("could not write \(outputPath)")
}

print("wrote \(outputPath)")
