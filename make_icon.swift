import Cocoa
import CoreGraphics

let size = 1024
let outDir = "/tmp/g3icon"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// Transparent canvas
cg.clear(CGRect(x: 0, y: 0, width: size, height: size))

// Standard macOS HIG icon grid: 824x824 squircle centered in 1024x1024
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = NSBezierPath(roundedRect: iconRect, xRadius: 185, yRadius: 185)

// Soft macOS drop shadow inside the 100px margin
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: NSColor(white: 0, alpha: 0.24).cgColor)
NSColor.white.setFill()
bgPath.fill()
cg.restoreGState()

// Crisp white-to-cool-gray gradient fill inside squircle
cg.saveGState()
bgPath.addClip()
let cs = CGColorSpaceCreateDeviceRGB()
let bgGrad = CGGradient(
    colorsSpace: cs,
    colors: [
        NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.92, green: 0.94, blue: 0.96, alpha: 1.0).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
)!
cg.drawLinearGradient(bgGrad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
cg.restoreGState()

// Subtle 2px inner rim highlight
NSColor(white: 0.86, alpha: 0.7).setStroke()
bgPath.lineWidth = 2
bgPath.stroke()

// Mouse silhouette (sleek dark graphite #1E242E) slightly right/bottom of center
let mouseRect = CGRect(x: 410, y: 245, width: 295, height: 470)
let mousePath = NSBezierPath(roundedRect: mouseRect, xRadius: 147.5, yRadius: 147.5)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: NSColor(white: 0, alpha: 0.16).cgColor)
let mouseGrad = CGGradient(
    colorsSpace: cs,
    colors: [
        NSColor(srgbRed: 0.20, green: 0.24, blue: 0.30, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.10, green: 0.13, blue: 0.18, alpha: 1.0).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
)!
mousePath.addClip()
cg.drawLinearGradient(mouseGrad, start: CGPoint(x: 557, y: 715), end: CGPoint(x: 557, y: 245), options: [])
cg.restoreGState()

// Button split line & scroll wheel
let splitLine = NSBezierPath()
splitLine.move(to: CGPoint(x: 557.5, y: 715))
splitLine.line(to: CGPoint(x: 557.5, y: 515))
NSColor(white: 1.0, alpha: 0.18).setStroke()
splitLine.lineWidth = 5
splitLine.stroke()

let wheelRect = CGRect(x: 542, y: 555, width: 31, height: 78)
let wheelPath = NSBezierPath(roundedRect: wheelRect, xRadius: 15.5, yRadius: 15.5)
NSColor(srgbRed: 0.20, green: 0.78, blue: 0.72, alpha: 1.0).setFill()
wheelPath.fill()

// Helper to draw a 4-point sparkle
func drawSparkle(center: CGPoint, radius: CGFloat, colors: [CGColor]) {
    let p = NSBezierPath()
    let inner = radius * 0.28
    p.move(to: CGPoint(x: center.x, y: center.y + radius))
    p.curve(to: CGPoint(x: center.x + radius, y: center.y),
            controlPoint1: CGPoint(x: center.x + inner * 0.35, y: center.y + inner),
            controlPoint2: CGPoint(x: center.x + inner, y: center.y + inner * 0.35))
    p.curve(to: CGPoint(x: center.x, y: center.y - radius),
            controlPoint1: CGPoint(x: center.x + inner, y: center.y - inner * 0.35),
            controlPoint2: CGPoint(x: center.x + inner * 0.35, y: center.y - inner))
    p.curve(to: CGPoint(x: center.x - radius, y: center.y),
            controlPoint1: CGPoint(x: center.x - inner * 0.35, y: center.y - inner),
            controlPoint2: CGPoint(x: center.x - inner, y: center.y - inner * 0.35))
    p.curve(to: CGPoint(x: center.x, y: center.y + radius),
            controlPoint1: CGPoint(x: center.x - inner, y: center.y + inner * 0.35),
            controlPoint2: CGPoint(x: center.x - inner * 0.35, y: center.y + inner))
    p.close()

    cg.saveGState()
    p.addClip()
    let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0.0, 1.0])!
    cg.drawLinearGradient(
        grad,
        start: CGPoint(x: center.x - radius, y: center.y + radius),
        end: CGPoint(x: center.x + radius, y: center.y - radius),
        options: []
    )
    cg.restoreGState()
}

let sparkleColors = [
    NSColor(srgbRed: 0.16, green: 0.82, blue: 0.72, alpha: 1.0).cgColor,
    NSColor(srgbRed: 0.14, green: 0.52, blue: 0.98, alpha: 1.0).cgColor
]
drawSparkle(center: CGPoint(x: 315, y: 695), radius: 92, colors: sparkleColors)
drawSparkle(center: CGPoint(x: 410, y: 780), radius: 44, colors: sparkleColors)

NSGraphicsContext.restoreGraphicsState()

if let png = rep.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: "\(outDir)/icon_1024.png"))
    print("Generated \(outDir)/icon_1024.png")
}
