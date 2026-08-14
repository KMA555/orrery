import AppKit

// ORRERYのリングを模したアプリアイコンを描いて1024pxのPNGにする
let size: CGFloat = 1024
let image = NSImage(size: CGSize(width: size, height: size))
image.lockFocus()

let cyan = NSColor(calibratedRed: 0.36, green: 0.86, blue: 1.0, alpha: 1)
let amber = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.20, alpha: 1)
let center = CGPoint(x: size / 2, y: size / 2)

// 背景（角丸の濃紺）
let inset: CGFloat = 40
let background = NSBezierPath(roundedRect: CGRect(x: inset, y: inset,
                                                  width: size - inset * 2, height: size - inset * 2),
                              xRadius: 200, yRadius: 200)
NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.08, alpha: 1).setFill()
background.fill()
background.addClip()

// 中心のにじみ
if let gradient = NSGradient(colors: [cyan.withAlphaComponent(0.22), cyan.withAlphaComponent(0)]) {
    gradient.draw(fromCenter: center, radius: 0, toCenter: center, radius: size * 0.42, options: [])
}

func arc(radius: CGFloat, width: CGFloat, from: CGFloat, sweep: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius,
                   startAngle: from, endAngle: from + sweep)
    path.lineWidth = width
    path.lineCapStyle = .butt
    color.setStroke()
    path.stroke()
}

// 外側の破断リング
arc(radius: size * 0.375, width: 26, from: 150, sweep: 158, color: cyan.withAlphaComponent(0.55))
arc(radius: size * 0.375, width: 26, from: 330, sweep: 148, color: cyan.withAlphaComponent(0.55))

// 内向きの櫛
let comb = NSBezierPath()
for index in 0..<72 {
    let degrees = CGFloat(index) / 72 * 360
    if degrees > 118 && degrees < 162 { continue }
    let radians = degrees * .pi / 180
    let outer = size * 0.335
    let inner = outer - size * 0.055
    comb.move(to: CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer))
    comb.line(to: CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner))
}
comb.lineWidth = 9
cyan.withAlphaComponent(0.6).setStroke()
comb.stroke()

// 琥珀のアクセント
arc(radius: size * 0.255, width: 13, from: 196, sweep: 62, color: amber.withAlphaComponent(0.9))

// いちばん明るい内側のリング
arc(radius: size * 0.205, width: 46, from: -72, sweep: 130, color: cyan)
arc(radius: size * 0.205, width: 46, from: 76, sweep: 122, color: cyan)
arc(radius: size * 0.205, width: 46, from: 212, sweep: 66, color: cyan)

// 中心の暗い抜き
NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.08, alpha: 1).setFill()
NSBezierPath(ovalIn: CGRect(x: center.x - size * 0.155, y: center.y - size * 0.155,
                            width: size * 0.31, height: size * 0.31)).fill()

// Oの字
let letter = NSBezierPath()
letter.appendArc(withCenter: center, radius: size * 0.098, startAngle: 0, endAngle: 360)
letter.lineWidth = 44
NSColor.white.setStroke()
letter.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
