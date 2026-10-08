#!/usr/bin/env swift

// Draws the 1024x1024 app icon: the Vysočina Region's own roads and rivers, with the
// app's bus and the letters VDV over them.
//
// Run through `make icon`, which fetches the region from OpenStreetMap the first time
// (tools/fetch-region-map.py) and caches it under build/. After that the icon can be
// redrawn offline, so changing a colour below is a one-line change and a re-run.
//
// The same artwork is written to both targets, so the phone app's icon and the watch
// app's cannot drift apart. App icons must be opaque: the bitmap is created without an
// alpha channel and iOS applies the rounded mask itself.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let outputPaths = [
    "VdvLive/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    "VdvLiveWatch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
]
let defaultRegionPath = "build/icon/region-map.json"
let stopsPath = "VdvLive/Resources/stop-positions.json"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Colours

typealias Tone = (red: Double, green: Double, blue: Double)

func colour(_ tone: Tone, alpha: Double = 1) -> CGColor {
    CGColor(red: tone.red, green: tone.green, blue: tone.blue, alpha: alpha)
}

let white: Tone = (1, 1, 1)

// MARK: - The region

struct Polyline {
    let points: [CGPoint]
}

/// Places coordinates in a square, keeping the ground proportions the region has
/// rather than the ones its degrees of longitude suggest.
struct Projection {
    let scale: CGFloat
    let offset: CGPoint
    let south: Double
    let west: Double
    let metresPerDegreeLatitude: Double = 111_132
    let metresPerDegreeLongitude: Double

    init(south: Double, west: Double, north: Double, east: Double, side: CGFloat, margin: CGFloat = 0.06) {
        let centreLatitude = (south + north) / 2
        self.south = south
        self.west = west
        metresPerDegreeLongitude = 111_132 * cos(centreLatitude * .pi / 180)

        let groundHeight = (north - south) * 111_132
        let groundWidth = (east - west) * metresPerDegreeLongitude
        let usable = side * (1 - 2 * margin)
        scale = min(usable / CGFloat(groundWidth), usable / CGFloat(groundHeight))
        offset = CGPoint(
            x: (side - CGFloat(groundWidth) * scale) / 2,
            y: (side - CGFloat(groundHeight) * scale) / 2
        )
    }

    func point(latitude: Double, longitude: Double) -> CGPoint {
        CGPoint(
            x: offset.x + CGFloat((longitude - west) * metresPerDegreeLongitude) * scale,
            y: offset.y + CGFloat((latitude - south) * metresPerDegreeLatitude) * scale
        )
    }
}

/// The region's bounding box, as the fetch wrote it out.
func loadBounds(from root: [String: Any]) -> (south: Double, west: Double, north: Double, east: Double) {
    guard let text = root["bbox"] as? String else {
        fail("the region's map has no bounding box; fetch it again with tools/fetch-region-map.py")
    }
    let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 4 else {
        fail("the region's bounding box is not \"south,west,north,east\": \(text)")
    }
    return (parts[0], parts[1], parts[2], parts[3])
}

struct MapLines {
    var motorway: [Polyline] = []
    var trunk: [Polyline] = []
    var primary: [Polyline] = []
    var river: [Polyline] = []

    var total: Int {
        motorway.count + trunk.count + primary.count + river.count
    }
}

func loadMapLines(from root: [String: Any], projection: Projection) -> MapLines {
    func lines(_ key: String) -> [Polyline] {
        (root[key] as? [[[Double]]] ?? []).compactMap { pairs in
            let points = pairs.compactMap { pair -> CGPoint? in
                guard pair.count == 2 else { return nil }
                return projection.point(latitude: pair[0], longitude: pair[1])
            }
            return points.count > 1 ? Polyline(points: points) : nil
        }
    }

    return MapLines(
        motorway: lines("motorway"),
        trunk: lines("trunk"),
        primary: lines("primary"),
        river: lines("river")
    )
}

// MARK: - The stops, as a grain

struct Stop {
    let latitude: Double
    let longitude: Double
}

func loadStops(from path: String) -> [Stop] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let stops = root["stops"] as? [String: [String: Any]] else {
        fail("cannot read the stop positions from \(path)")
    }

    return stops.values.compactMap { record in
        guard let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double else { return nil }
        return Stop(latitude: latitude, longitude: longitude)
    }
}

// MARK: - The bus, as a mask

struct Bus {
    let mask: CGImage
    let canvas: CGFloat
    let centre: CGPoint
    let extent: CGFloat
}

/// Draws an SF Symbol into a square of its own and turns the ink into a mask.
///
/// A symbol is black pixels inside an alpha shape, so painting it straight into the
/// icon would composite the black rather than the white. The palette makes it white
/// first, and the mask then lets it be drawn in any colour.
func loadBus(canvas: Int, pointSize: CGFloat) -> Bus {
    guard let symbol = NSImage(systemSymbolName: "bus.fill", accessibilityDescription: nil) else {
        fail("the SF Symbol bus.fill is not available")
    }
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let glyph = symbol.withSymbolConfiguration(configuration) else {
        fail("could not configure the SF Symbol bus.fill")
    }

    let space = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: canvas * canvas * 4)
    guard let context = CGContext(
        data: &pixels,
        width: canvas,
        height: canvas,
        bitsPerComponent: 8,
        bytesPerRow: canvas * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("could not create the bus's drawing context")
    }

    let size = glyph.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    glyph.draw(in: NSRect(
        x: (CGFloat(canvas) - size.width) / 2,
        y: (CGFloat(canvas) - size.height) / 2,
        width: size.width,
        height: size.height
    ))
    NSGraphicsContext.restoreGraphicsState()

    var mask = [UInt8](repeating: 0, count: canvas * canvas)
    var minX = canvas, minY = canvas, maxX = 0, maxY = 0
    for y in 0..<canvas {
        for x in 0..<canvas {
            let index = (y * canvas + x) * 4
            let weakest = Int(min(pixels[index], min(pixels[index + 1], pixels[index + 2])))
            let whiteness = max(0, min(255, Int(Double(weakest - 9) / Double(255 - 9) * 255)))
            // Inverted: CoreGraphics image masks paint where they are dark.
            mask[y * canvas + x] = UInt8(255 - whiteness)
            if whiteness > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX > minX else {
        fail("the bus glyph came out empty")
    }

    guard let provider = CGDataProvider(data: Data(mask) as CFData),
          let image = CGImage(
            maskWidth: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: canvas,
            provider: provider,
            decode: nil,
            shouldInterpolate: true
          ) else {
        fail("could not build the bus mask")
    }

    return Bus(
        mask: image,
        canvas: CGFloat(canvas),
        centre: CGPoint(
            x: (CGFloat(minX) + CGFloat(maxX)) / 2,
            y: (CGFloat(minY) + CGFloat(maxY)) / 2
        ),
        extent: CGFloat(max(maxX - minX, maxY - minY))
    )
}

func drawBus(_ bus: Bus, in context: CGContext, ink: Tone, target: CGFloat, centre: CGPoint) {
    let scale = target / bus.extent
    context.saveGState()
    context.setFillColor(colour(ink))
    context.translateBy(x: centre.x, y: centre.y)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -bus.centre.x, y: -bus.centre.y)
    context.clip(
        to: CGRect(x: 0, y: 0, width: bus.canvas, height: bus.canvas),
        mask: bus.mask
    )
    context.fill(CGRect(x: 0, y: 0, width: bus.canvas, height: bus.canvas))
    context.restoreGState()
}

// MARK: - Drawing

func drawGradient(_ context: CGContext, from: Tone, to: Tone) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [colour(from), colour(to)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(side)),
        end: CGPoint(x: CGFloat(side), y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func stroke(_ lines: [Polyline], in context: CGContext, ink: Tone, alpha: Double, width: CGFloat) {
    guard !lines.isEmpty else { return }
    context.saveGState()
    context.setStrokeColor(colour(ink, alpha: alpha))
    context.setLineWidth(width)
    // Round caps and joins are what make a road network read as one connected thing.
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for line in lines {
        context.beginPath()
        context.move(to: line.points[0])
        for point in line.points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }
    context.restoreGState()
}

@discardableResult
func drawWord(_ text: String, in context: CGContext, ink: Tone, size: CGFloat, centre: CGPoint) -> CGFloat {
    let spacing = size * 0.11
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    // CoreText draws with the attribute, not with the context's fill, so the ink has
    // to be in the attributes or a dark word comes out white.
    let nsInk = NSColor(calibratedRed: ink.red, green: ink.green, blue: ink.blue, alpha: 1)
    let attributed = NSAttributedString(
        string: text,
        attributes: [.font: font, .foregroundColor: nsInk, .kern: spacing]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let measured = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let inked = measured - CGFloat(spacing)

    context.saveGState()
    context.setFillColor(colour(ink))
    context.textPosition = CGPoint(x: centre.x - inked / 2, y: centre.y - (ascent - descent) / 2)
    CTLineDraw(line, context)
    context.restoreGState()
    return inked
}

func render(stops: [Stop], projection: Projection, map: MapLines, bus: Bus, context: CGContext) {
    let side = CGFloat(side)

    // Deep navy in the south west, a lighter blue in the north east: the map has to stay
    // quiet enough for the white bus and the motorways to read on top of it.
    drawGradient(context, from: (0.05, 0.08, 0.20), to: (0.07, 0.15, 0.35))

    // Water sits under everything else, as it does on a map. Only the rivers are drawn:
    // the region's standing water comes back from OpenStreetMap as very large, often
    // unnamed polygons, and filling those turns the icon into blocks of pale blue.
    stroke(map.river, in: context, ink: (0.16, 0.42, 0.72), alpha: 0.55, width: 3)

    // The stops as a grain: the region's shape, its settlements, without competing with
    // the roads.
    context.setFillColor(colour(white, alpha: 0.12))
    for stop in stops {
        let point = projection.point(latitude: stop.latitude, longitude: stop.longitude)
        context.fillEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
    }

    // The roads a map shows at a glance: the motorways and the numbered routes. The
    // region's minor roads are a mesh at this size, and drawing them turns the whole icon
    // into a spider web. The strokes stay thin because a short way under a round cap
    // becomes a disc, and OpenStreetMap splits the D1 and the D35 into thousands of ways,
    // many of them a few hundred metres long: at icon size, a couple of pixels.
    stroke(map.primary, in: context, ink: (0.62, 0.69, 0.82), alpha: 0.45, width: 2.5)
    stroke(map.trunk, in: context, ink: (0.78, 0.83, 0.92), alpha: 0.75, width: 6)
    stroke(map.motorway, in: context, ink: (0.95, 0.97, 1.0), alpha: 0.95, width: 7)

    // The bus above the middle, the word below it, both clear of the rounded corners iOS
    // cuts away.
    drawBus(
        bus, in: context, ink: white,
        target: side * 0.40, centre: CGPoint(x: side / 2, y: side * 0.615)
    )
    drawWord(
        "VDV", in: context, ink: white,
        size: side * 0.18, centre: CGPoint(x: side / 2, y: side * 0.16)
    )
}

func makeImage(_ draw: (CGContext) -> Void) -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fail("could not create the drawing context")
    }
    draw(context)
    guard let image = context.makeImage() else {
        fail("could not render the icon")
    }
    return image
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fail("could not create \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("could not write \(path)")
    }
}

// MARK: - Draw it

let regionPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultRegionPath
guard let regionData = try? Data(contentsOf: URL(fileURLWithPath: regionPath)),
      let regionRoot = try? JSONSerialization.jsonObject(with: regionData) as? [String: Any] else {
    fail("cannot read the region's map from \(regionPath) - run tools/fetch-region-map.py first")
}

let bounds = loadBounds(from: regionRoot)
let projection = Projection(
    south: bounds.south,
    west: bounds.west,
    north: bounds.north,
    east: bounds.east,
    side: CGFloat(side)
)
let map = loadMapLines(from: regionRoot, projection: projection)
let stops = loadStops(from: stopsPath)
let bus = loadBus(canvas: side, pointSize: CGFloat(side) * 0.44)

print(
    "region: \(map.motorway.count) motorway, \(map.trunk.count) trunk, "
        + "\(map.primary.count) primary, \(map.river.count) river ways"
)
print("bus: \(Int(bus.extent)) px of ink, \(stops.count) stops as a grain")

let image = makeImage { context in
    render(stops: stops, projection: projection, map: map, bus: bus, context: context)
}
for path in outputPaths {
    write(image, to: path)
    print("wrote \(path)")
}
