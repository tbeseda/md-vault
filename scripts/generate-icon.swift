// Regenerates the app icon in both formats: AppIcon.icon (Icon Composer
// package; macOS 26 requires it for apps deploying against SDK 26, else the
// Dock shows the grid placeholder) and AppIcon.appiconset (classic icns for
// Finder/older contexts). Flat, single-color: the Markdown Mark glyph
// (Dustin Curtis, CC0) centered on a macOS squircle.
//
//   swift scripts/generate-icon.swift [glyphHex] [backgroundHex]
//
// Defaults: white mark on near-black. Run from the repo root.

import AppKit
import UniformTypeIdentifiers

let glyphHex = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "FFFFFF"
let paperHex = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "111214"

func color(_ hex: String) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

// The Markdown Mark's two filled subpaths, in its 208x128 top-down SVG
// space. Glyph bounds: x 30...185, y 30...98.
let mSubpath: [CGPoint] = [
    .init(x: 30, y: 98), .init(x: 30, y: 30), .init(x: 50, y: 30), .init(x: 70, y: 55),
    .init(x: 90, y: 30), .init(x: 110, y: 30), .init(x: 110, y: 98), .init(x: 90, y: 98),
    .init(x: 90, y: 59), .init(x: 70, y: 84), .init(x: 50, y: 59), .init(x: 50, y: 98),
]
let arrowSubpath: [CGPoint] = [
    .init(x: 155, y: 98), .init(x: 125, y: 65), .init(x: 145, y: 65), .init(x: 145, y: 30),
    .init(x: 165, y: 30), .init(x: 165, y: 65), .init(x: 185, y: 65),
]

func render(px: Int) -> Data {
    let context = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let canvas = CGFloat(px)

    // Apple's macOS icon grid: 824pt squircle centered in a 1024pt canvas.
    let inset = canvas * 100 / 1024
    let squircle = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let cornerRadius = canvas * 185.4 / 1024
    context.addPath(CGPath(roundedRect: squircle, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.setFillColor(color(paperHex))
    context.fillPath()

    // Center the glyph at 56% of the squircle's width, flipping SVG y-down
    // coordinates to CoreGraphics y-up.
    let scale = squircle.width * 0.56 / 155
    let originX = (canvas - 155 * scale) / 2
    let originY = (canvas - 68 * scale) / 2
    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: originX + (p.x - 30) * scale, y: originY + (98 - p.y) * scale)
    }
    let glyph = CGMutablePath()
    for subpath in [mSubpath, arrowSubpath] {
        glyph.addLines(between: subpath.map(point))
        glyph.closeSubpath()
    }
    context.addPath(glyph)
    context.setFillColor(color(glyphHex))
    context.fillPath()

    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let outputDirectory = URL(filePath: "MDVault/Assets.xcassets/AppIcon.appiconset")
let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    try render(px: size).write(to: outputDirectory.appending(path: "icon_\(size).png"))
    try render(px: size * 2).write(to: outputDirectory.appending(path: "icon_\(size)@2x.png"))
    print("icon_\(size).png / @2x")
}

// The Icon Composer package: a transparent glyph layer over a solid fill;
// the system draws the squircle, glass, and shadows itself. The layer canvas
// IS the squircle face, so the glyph keeps the same 56%-of-face proportion.
func renderMarkLayer(px: Int) -> Data {
    let context = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let canvas = CGFloat(px)
    let scale = canvas * 0.56 / 155
    let originX = (canvas - 155 * scale) / 2
    let originY = (canvas - 68 * scale) / 2
    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: originX + (p.x - 30) * scale, y: originY + (98 - p.y) * scale)
    }
    let glyph = CGMutablePath()
    for subpath in [mSubpath, arrowSubpath] {
        glyph.addLines(between: subpath.map(point))
        glyph.closeSubpath()
    }
    context.addPath(glyph)
    context.setFillColor(color(glyphHex))
    context.fillPath()
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func srgbComponents(_ hex: String) -> String {
    let v = UInt32(hex, radix: 16)!
    return String(
        format: "%.5f,%.5f,%.5f,1.00000",
        Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255
    )
}

let iconPackage = URL(filePath: "MDVault/AppIcon.icon")
try FileManager.default.createDirectory(at: iconPackage.appending(path: "Assets"), withIntermediateDirectories: true)
try renderMarkLayer(px: 1024).write(to: iconPackage.appending(path: "Assets/mark.png"))
let iconJSON = """
{
  "fill" : {
    "solid" : "srgb:\(srgbComponents(paperHex))"
  },
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "mark.png",
          "name" : "mark"
        }
      ]
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}
"""
try iconJSON.write(to: iconPackage.appending(path: "icon.json"), atomically: true, encoding: .utf8)
print("AppIcon.icon")

let entries = sizes.flatMap { size in
    [
        "    { \"idiom\" : \"mac\", \"scale\" : \"1x\", \"size\" : \"\(size)x\(size)\", \"filename\" : \"icon_\(size).png\" }",
        "    { \"idiom\" : \"mac\", \"scale\" : \"2x\", \"size\" : \"\(size)x\(size)\", \"filename\" : \"icon_\(size)@2x.png\" }",
    ]
}
let contents = "{\n  \"images\" : [\n" + entries.joined(separator: ",\n")
    + "\n  ],\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"
try contents.write(to: outputDirectory.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Contents.json")
