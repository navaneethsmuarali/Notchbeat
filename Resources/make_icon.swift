import AppKit
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 1, green: 0.16, blue: 0.2, alpha: 1), ending: NSColor(red: 0.62, green: 0.02, blue: 0.1, alpha: 1))!.draw(in: body, angle: -90)
// island pill
NSColor.black.setFill()
NSBezierPath(roundedRect: NSRect(x: 312, y: 760, width: 400, height: 92), xRadius: 46, yRadius: 46).fill()
NSColor(red: 1, green: 0.3, blue: 0.35, alpha: 1).setFill()
for (i, h) in [36.0, 60, 28, 50].enumerated() {
  NSBezierPath(roundedRect: NSRect(x: 600 + Double(i) * 22, y: 806 - h / 2, width: 12, height: h), xRadius: 6, yRadius: 6).fill()
}
NSColor.white.withAlphaComponent(0.9).setFill()
NSBezierPath(roundedRect: NSRect(x: 340, y: 778, width: 56, height: 56), xRadius: 14, yRadius: 14).fill()
// ring + play
NSColor.white.setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 292, y: 182, width: 440, height: 440)); ring.lineWidth = 34; ring.stroke()
NSColor.white.setFill()
let tri = NSBezierPath(); tri.move(to: NSPoint(x: 450, y: 302)); tri.line(to: NSPoint(x: 450, y: 502)); tri.line(to: NSPoint(x: 620, y: 402)); tri.close(); tri.fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
