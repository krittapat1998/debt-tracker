import AppKit

// usage:
//   swift tool/screenshots/showcase.swift hero <out.png> <icon.png> <left.png> <center.png> <right.png>
//   swift tool/screenshots/showcase.swift frame <out.png> <screen.png> <width>
//   swift tool/screenshots/showcase.swift gallery <out.png> (<screen.png> <caption>)...

func font(_ name: String, _ size: CGFloat) -> NSFont { NSFont(name: name, size: size) ?? .systemFont(ofSize: size) }
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func canvas(_ w: Int, _ h: Int, _ draw: (NSSize) -> Void) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  let ctx = NSGraphicsContext(bitmapImageRep: rep)!
  ctx.imageInterpolation = .high
  NSGraphicsContext.current = ctx
  draw(NSSize(width: w, height: h))
  NSGraphicsContext.restoreGraphicsState()
  return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
  print(path)
}

/// A plain phone: dark body, thin bezel, the screenshot with rounded corners. `x, y` is the body's bottom-left.
func phone(_ img: NSImage, x: CGFloat, y: CGFloat, width: CGFloat, shadow: Bool = true) {
  let bezel = width * 0.032
  let sw = width - bezel * 2
  let sh = sw * img.size.height / img.size.width
  let body = NSRect(x: x, y: y, width: width, height: sh + bezel * 2)
  let screenRadius = sw * 0.135
  let bodyPath = NSBezierPath(roundedRect: body, xRadius: screenRadius + bezel, yRadius: screenRadius + bezel)
  NSGraphicsContext.saveGraphicsState()
  if shadow {
    let s = NSShadow()
    s.shadowColor = NSColor(white: 0, alpha: 0.35)
    s.shadowBlurRadius = width * 0.09
    s.shadowOffset = NSSize(width: 0, height: -width * 0.035)
    s.set()
  }
  rgb(0x121417).setFill(); bodyPath.fill()
  NSGraphicsContext.restoreGraphicsState()
  // A faint rim so the dark body reads on dark backgrounds too.
  rgb(0x3A3F47).setStroke(); bodyPath.lineWidth = max(1, width * 0.004); bodyPath.stroke()
  let screen = NSRect(x: x + bezel, y: y + bezel, width: sw, height: sh)
  NSGraphicsContext.saveGraphicsState()
  NSBezierPath(roundedRect: screen, xRadius: screenRadius, yRadius: screenRadius).addClip()
  img.draw(in: screen)
  NSGraphicsContext.restoreGraphicsState()
}

func phoneHeight(_ img: NSImage, width: CGFloat) -> CGFloat {
  let bezel = width * 0.032
  return (width - bezel * 2) * img.size.height / img.size.width + bezel * 2
}

func text(_ s: String, _ f: NSFont, _ c: NSColor, at p: NSPoint, kern: CGFloat = 0) {
  (s as NSString).draw(at: p, withAttributes: [.font: f, .foregroundColor: c, .kern: kern])
}

func textSize(_ s: String, _ f: NSFont) -> NSSize { (s as NSString).size(withAttributes: [.font: f]) }

let args = Array(CommandLine.arguments.dropFirst())
switch args[0] {
case "frame":
  let img = NSImage(contentsOfFile: args[2])!
  let w = CGFloat(Double(args[3])!)
  let pad = w * 0.12
  let h = phoneHeight(img, width: w)
  save(canvas(Int(w + pad * 2), Int(h + pad * 2)) { _ in phone(img, x: pad, y: pad, width: w) }, args[1])

case "hero":
  let icon = NSImage(contentsOfFile: args[2])!
  let shots = args[3...5].map { NSImage(contentsOfFile: $0)! }
  let W = 2400, H = 1260
  save(canvas(W, H) { size in
    NSGradient(colors: [rgb(0x0A2A7A), rgb(0x1556E0), rgb(0x2F86F6)])!
      .draw(in: NSRect(origin: .zero, size: size), angle: 35)
    // Soft light blobs.
    for (cx, cy, r, a) in [(1850.0, 1120.0, 520.0, 0.10), (1500.0, 120.0, 380.0, 0.07), (260.0, 1180.0, 300.0, 0.06)] {
      rgb(0xFFFFFF, a).setFill()
      NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()
    }
    // Text column.
    let left: CGFloat = 130
    let iconSize: CGFloat = 150
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowColor = NSColor(white: 0, alpha: 0.3); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -10); s.set()
    let iconRect = NSRect(x: left, y: 860, width: iconSize, height: iconSize)
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: iconSize * 0.225, yRadius: iconSize * 0.225)
    rgb(0x1556E0).setFill(); iconPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState(); iconPath.addClip(); icon.draw(in: iconRect); NSGraphicsContext.restoreGraphicsState()

    text("Debt Tracker", font("SukhumvitSet-Bold", 112), .white, at: NSPoint(x: left - 6, y: 690), kern: -1.5)
    text("ติดตามหนี้บัตรเครดิต บัตรกดเงินสด สินเชื่อ", font("SukhumvitSet-SemiBold", 50), rgb(0xFFFFFF, 0.95), at: NSPoint(x: left, y: 610))
    text("และวางแผนปลดหนี้ ในแอพเดียว", font("SukhumvitSet-SemiBold", 50), rgb(0xFFFFFF, 0.95), at: NSPoint(x: left, y: 540))
    text("Personal debt tracker & payoff planner for Thai cards and loans",
         font("SukhumvitSet-Medium", 31), rgb(0xD6E6FF), at: NSPoint(x: left, y: 470))

    // Chips.
    var cx = left
    var cy: CGFloat = 340
    let chipFont = font("SukhumvitSet-SemiBold", 30)
    for chip in ["แผนปลดหนี้", "ปฏิทินครบกำหนด", "ดอกเบี้ยรายวัน", "นำเข้า SMS", "Face ID", "ข้อมูลอยู่ในเครื่อง"] {
      let ts = textSize(chip, chipFont)
      var r = NSRect(x: cx, y: cy, width: ts.width + 52, height: 70)
      if r.maxX > 1060 { cx = left; cy -= 92; r.origin = NSPoint(x: cx, y: cy) }
      rgb(0xFFFFFF, 0.16).setFill()
      NSBezierPath(roundedRect: NSRect(x: cx, y: cy, width: r.width, height: r.height), xRadius: 35, yRadius: 35).fill()
      text(chip, chipFont, .white, at: NSPoint(x: cx + 26, y: cy + (70 - ts.height) / 2))
      cx += r.width + 16
    }
    text("Flutter  ·  Riverpod  ·  SQLite  ·  iOS & Android", font("SukhumvitSet-Medium", 30), rgb(0xFFFFFF, 0.75),
         at: NSPoint(x: left, y: 120))

    // Phones: two behind, one in front.
    let back: CGFloat = 470, front: CGFloat = 540
    phone(shots[0], x: 1190, y: 140, width: back)
    phone(shots[2], x: 1830, y: 140, width: back)
    phone(shots[1], x: 1475, y: 30, width: front)
  }, args[1])

case "gallery":
  var items: [(NSImage, String)] = []
  var i = 2
  while i + 1 < args.count { items.append((NSImage(contentsOfFile: args[i])!, args[i + 1])); i += 2 }
  let pw: CGFloat = 430, gap: CGFloat = 70, side: CGFloat = 110, top: CGFloat = 150, bottom: CGFloat = 90
  let ph = items.map { phoneHeight($0.0, width: pw) }.max()!
  let W = Int(side * 2 + CGFloat(items.count) * pw + CGFloat(items.count - 1) * gap)
  let H = Int(top + ph + bottom)
  save(canvas(W, H) { size in
    NSGradient(colors: [rgb(0xEEF4FB), rgb(0xDCE9F8)])!.draw(in: NSRect(origin: .zero, size: size), angle: 90)
    let capFont = font("SukhumvitSet-Bold", 40)
    for (n, (img, cap)) in items.enumerated() {
      let x = side + CGFloat(n) * (pw + gap)
      let ts = textSize(cap, capFont)
      text(cap, capFont, rgb(0x0F2A3D), at: NSPoint(x: x + (pw - ts.width) / 2, y: size.height - top + 40))
      phone(img, x: x, y: bottom, width: pw)
    }
  }, args[1])

default:
  fatalError("unknown mode \(args[0])")
}
