// Draws the App Store creative assets from the app's own icon.
//
// Creative assets are the wide banners the App Store shows on the product page
// header and in search results (iOS 27 and later). App Store Connect accepts two
// sizes; both are drawn here, at the proportions that suit each:
//
//   swift tools/make-appstore-banner.swift 5244 2950 <icon.png> <out.png>
//   swift tools/make-appstore-banner.swift 3840 1646 <icon.png> <out.png>
//
// The composition is centred and kept inside a margin, because the App Store
// crops these differently depending on where it shows them. Run the output
// through tools/strip-png-metadata.py before uploading: ImageIO stamps an eXIf
// chunk, and the uploader refuses a PNG that carries metadata - with an error
// that blames the dimensions.

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Draws a wide App Store creative asset from the app's own icon: the icon's navy
/// field as the background, the icon itself, and the app's name.
func banner(width: Int, height: Int, iconPath: String, outPath: String) -> Bool {
    let side = CGFloat(height)
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: iconPath) as CFURL, nil),
          let icon = CGImageSourceCreateImageAtIndex(src, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }

    // The icon's own field: a navy that deepens towards the bottom.
    let colours = [
        CGColor(srgbRed: 0.055, green: 0.118, blue: 0.290, alpha: 1),
        CGColor(srgbRed: 0.031, green: 0.071, blue: 0.192, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side),
                               end: CGPoint(x: 0, y: 0), options: [])
    }

    // A faint glow behind the icon, so the field is not a flat sheet.
    if let glow = CGGradient(colorsSpace: space,
                             colors: [CGColor(srgbRed: 0.20, green: 0.36, blue: 0.72, alpha: 0.55),
                                      CGColor(srgbRed: 0.20, green: 0.36, blue: 0.72, alpha: 0)] as CFArray,
                             locations: [0, 1]) {
        let centre = CGPoint(x: CGFloat(width) * 0.5 - side * 0.30, y: side * 0.5)
        ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: side * 0.62, options: [])
    }

    let iconSide = side * 0.54
    let radius = iconSide * 0.2237

    // Text, to the right of the icon. Laid out after measuring, so the whole
    // lockup can be centred and kept clear of the edges: the asset is cropped
    // differently depending on where the App Store shows it.
    func line(_ string: String, size: CGFloat, weight: NSFont.Weight, colour: CGColor) -> (CTLine, CGRect, CGColor) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: colour) ?? .white,
            .kern: -size * 0.015,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        return (line, CTLineGetBoundsWithOptions(line, .useOpticalBounds), colour)
    }

    func draw(_ drawn: (CTLine, CGRect, CGColor), x: CGFloat, y: CGFloat) {
        ctx.textPosition = CGPoint(x: x - drawn.1.origin.x, y: y - drawn.1.origin.y)
        CTLineDraw(drawn.0, ctx)
    }

    let title = line("VDV Live", size: side * 0.135, weight: .bold,
                     colour: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    let subtitle = line("Live buses and trains in the Vysočina Region",
                        size: side * 0.052, weight: .medium,
                        colour: CGColor(srgbRed: 0.78, green: 0.85, blue: 1, alpha: 1))
    let czech = line("Veřejná doprava Vysočiny", size: side * 0.045, weight: .regular,
                     colour: CGColor(srgbRed: 0.62, green: 0.72, blue: 0.92, alpha: 1))

    let gap = side * 0.10
    let textWidth = max(title.1.width, max(subtitle.1.width, czech.1.width))
    let blockWidth = iconSide + gap + textWidth
    let margin = side * 0.06
    let startX = max(margin, (CGFloat(width) - blockWidth) / 2)

    let iconRect = CGRect(x: startX, y: (side - iconSide) / 2, width: iconSide, height: iconSide)

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: radius, cornerHeight: radius,
                       transform: nil))
    ctx.clip()
    ctx.draw(icon, in: iconRect)
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: radius, cornerHeight: radius,
                       transform: nil))
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.20))
    ctx.setLineWidth(max(side * 0.004, 2))
    ctx.strokePath()
    let textX = startX + iconSide + gap
    let titleY = side * 0.505
    let subtitleY = side * 0.505 - side * 0.135 * 1.05

    draw(title, x: textX, y: titleY)
    draw(subtitle, x: textX, y: subtitleY)
    draw(czech, x: textX, y: subtitleY - side * 0.052 * 1.5)

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

let args = CommandLine.arguments
guard args.count == 5, let w = Int(args[1]), let h = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: make-banner <w> <h> <icon> <out>\n".utf8))
    exit(2)
}
exit(banner(width: w, height: h, iconPath: args[3], outPath: args[4]) ? 0 : 1)
