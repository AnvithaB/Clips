import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let symbolName = CommandLine.arguments[2]
let colors: [String: NSColor] = [
    "clipboard": NSColor(calibratedRed: 0.11, green: 0.48, blue: 0.49, alpha: 1),
    "screenshots": NSColor(calibratedRed: 0.29, green: 0.36, blue: 0.65, alpha: 1),
    "notes": NSColor(calibratedRed: 0.75, green: 0.48, blue: 0.23, alpha: 1)
]
let color = colors[CommandLine.arguments[3]] ?? NSColor(calibratedRed: 0.15, green: 0.38, blue: 0.43, alpha: 1)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let side = CGFloat(pixels)
        let tile = NSBezierPath(roundedRect: NSRect(x: side * 0.06, y: side * 0.06, width: side * 0.88, height: side * 0.88), xRadius: side * 0.2, yRadius: side * 0.2)
        NSGradient(starting: color.blended(withFraction: 0.2, of: .white)!, ending: color.blended(withFraction: 0.32, of: .black)!)!.draw(in: tile, angle: -70)
        NSColor.white.withAlphaComponent(0.22).setStroke(); tile.lineWidth = side * 0.012; tile.stroke()
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ fill: NSColor) {
            fill.setFill(); NSBezierPath(roundedRect: NSRect(x: x * side, y: y * side, width: w * side, height: h * side), xRadius: radius * side, yRadius: radius * side).fill()
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, _ fill: NSColor) {
            fill.setFill(); NSBezierPath(ovalIn: NSRect(x: x * side, y: y * side, width: d * side, height: d * side)).fill()
        }
        switch CommandLine.arguments[3] {
        case "clipboard":
            box(0.24, 0.20, 0.48, 0.59, 0.055, .white.withAlphaComponent(0.30))
            box(0.30, 0.17, 0.48, 0.59, 0.055, .white)
            box(0.42, 0.71, 0.23, 0.09, 0.035, color.blended(withFraction: 0.25, of: .white)!)
            for y: CGFloat in [0.56, 0.44, 0.32] { box(0.39, y, y == 0.32 ? 0.17 : 0.29, 0.035, 0.017, color.withAlphaComponent(0.8)) }
        case "screenshots":
            box(0.18, 0.27, 0.64, 0.43, 0.085, .white)
            box(0.31, 0.65, 0.25, 0.10, 0.035, .white)
            circle(0.35, 0.32, 0.32, color)
            circle(0.40, 0.37, 0.22, color.blended(withFraction: 0.40, of: .black)!)
            circle(0.43, 0.48, 0.065, .white.withAlphaComponent(0.7))
            circle(0.71, 0.59, 0.045, color)
        case "notes":
            box(0.23, 0.19, 0.54, 0.63, 0.055, NSColor(calibratedRed: 1, green: 0.96, blue: 0.82, alpha: 1))
            for y: CGFloat in [0.65, 0.54, 0.43] { box(0.32, y, 0.32, 0.026, 0.013, color.withAlphaComponent(0.6)) }
            let pencil = NSBezierPath(); pencil.move(to: NSPoint(x: side * 0.53, y: side * 0.25)); pencil.line(to: NSPoint(x: side * 0.78, y: side * 0.58)); pencil.lineWidth = side * 0.08; pencil.lineCapStyle = .round
            NSColor(calibratedRed: 0.97, green: 0.46, blue: 0.18, alpha: 1).setStroke(); pencil.stroke()
        default:
            let font = NSFont.systemFont(ofSize: side * 0.54, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let mark = "P." as NSString
            let measured = mark.size(withAttributes: attributes)
            mark.draw(at: NSPoint(x: (side - measured.width) / 2, y: (side - measured.height) / 2), withAttributes: attributes)
        }
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
