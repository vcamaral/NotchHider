// Draws the app icon. Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Notch silhouette hanging from `top`, with the outward fillets where it meets the bezel.
func notchPath(centerX cx: CGFloat, top: CGFloat, width w: CGFloat, height h: CGFloat, radius r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let left = cx - w / 2, right = cx + w / 2, bottom = top - h
    p.move(to: CGPoint(x: left - r, y: top))
    p.addQuadCurve(to: CGPoint(x: left, y: top - r), control: CGPoint(x: left, y: top))
    p.addLine(to: CGPoint(x: left, y: bottom + r))
    p.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
    p.addLine(to: CGPoint(x: right - r, y: bottom))
    p.addQuadCurve(to: CGPoint(x: right, y: bottom + r), control: CGPoint(x: right, y: bottom))
    p.addLine(to: CGPoint(x: right, y: top - r))
    p.addQuadCurve(to: CGPoint(x: right + r, y: top), control: CGPoint(x: right, y: top))
    p.closeSubpath()
    return p
}

// macOS icon grid: 824pt body inside a 1024 canvas, with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x5b8cff)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()

// Wallpaper gradient.
let gradient = CGGradient(colorsSpace: rgb, colors: [color(0x5b8cff), color(0x8b5cf6), color(0xec4899)] as CFArray,
                          locations: nil)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY),
                       end: CGPoint(x: body.maxX, y: body.minY), options: [])

// Black menu bar band, with the notch barely visible inside it.
let bandHeight: CGFloat = 300
ctx.setFillColor(color(0x000000))
ctx.fill(CGRect(x: 0, y: body.maxY - bandHeight, width: size, height: bandHeight))
ctx.addPath(notchPath(centerX: body.midX, top: body.maxY, width: 300, height: 130, radius: 40))
ctx.setFillColor(color(0x26262c)); ctx.fillPath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
