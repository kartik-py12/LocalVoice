import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let side = 1024
let image = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
let context = NSGraphicsContext(bitmapImageRep: image)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 220, yRadius: 220)
NSGradient(colors: [
    NSColor(calibratedRed: 0.31, green: 0.29, blue: 0.86, alpha: 1),
    NSColor(calibratedRed: 0.50, green: 0.37, blue: 0.94, alpha: 1)
])!.draw(in: tile, angle: 315)

let bars: [(CGFloat, CGFloat)] = [
    (274, 140), (360, 240), (446, 350), (532, 440),
    (618, 350), (704, 240), (790, 140)
]
NSColor.white.withAlphaComponent(0.96).setStroke()
for (x, height) in bars {
    let path = NSBezierPath()
    path.lineWidth = 42
    path.lineCapStyle = .round
    path.move(to: NSPoint(x: x, y: 512 - height / 2))
    path.line(to: NSPoint(x: x, y: 512 + height / 2))
    path.stroke()
}

NSGraphicsContext.restoreGraphicsState()
guard let png = image.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the LocalVoice app icon.")
}
try png.write(to: outputURL)
