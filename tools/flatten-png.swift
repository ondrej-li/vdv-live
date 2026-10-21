// Rewrites a PNG as an opaque image, keeping the dimensions App Store Connect asks for.
//
// Simulator screenshots (`simctl io … screenshot`) are written with an alpha
// channel. App Store artwork must not have one, and the uploader refuses it. This
// draws the image into an opaque sRGB context and writes a fresh PNG.
//
//   swift tools/flatten-png.swift <in.png> <out.png> [width height]
//
// Without width/height the source size is kept. Pair it with
// tools/strip-png-metadata.py: this removes the alpha, that removes the eXIf
// chunk ImageIO stamps on the way out.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 || args.count == 5 else {
    FileHandle.standardError.write(Data("usage: flatten-png <in> <out> [width height]\n".utf8))
    exit(2)
}
let source = URL(fileURLWithPath: args[1])
let destination = URL(fileURLWithPath: args[2])

guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(source.path)\n".utf8))
    exit(1)
}

let width = args.count == 5 ? Int(args[3]) ?? image.width : image.width
let height = args.count == 5 ? Int(args[4]) ?? image.height : image.height

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      ) else {
    FileHandle.standardError.write(Data("cannot make a context\n".utf8))
    exit(1)
}
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let flattened = context.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        destination as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else {
    FileHandle.standardError.write(Data("cannot write \(destination.path)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(dest, flattened, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
