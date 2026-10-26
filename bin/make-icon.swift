import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32), ("icon_32x32@2x",64),
                       ("icon_128x128",128), ("icon_128x128@2x",256), ("icon_256x256",256),
                       ("icon_256x256@2x",512), ("icon_512x512",512), ("icon_512x512@2x",1024)] {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let inset = size * 0.055
    let rect = NSRect(x: inset, y: inset, width: size-inset*2, height: size-inset*2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: size*0.2, yRadius: size*0.2)
    NSGradient(starting: NSColor(red: 0.18, green: 0.15, blue: 0.44, alpha: 1),
               ending: NSColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 1))!.draw(in: shape, angle: -60)
    for degrees in [0.0, 60.0, 120.0] {
        NSGraphicsContext.saveGraphicsState()
        let transform = AffineTransform(translationByX: size/2, byY: size/2)
        var rotation = transform
        rotation.rotate(byDegrees: degrees)
        (rotation as NSAffineTransform).concat()
        let orbit = NSBezierPath(ovalIn: NSRect(x: -size*0.31, y: -size*0.12, width: size*0.62, height: size*0.24))
        orbit.lineWidth = max(1, size*0.027)
        NSColor(red: 0.65, green: 0.76, blue: 1, alpha: 0.95).setStroke()
        orbit.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSColor(red: 0.98, green: 0.73, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: size*0.44, y: size*0.44, width: size*0.12, height: size*0.12)).fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/\(name).png"))
}
