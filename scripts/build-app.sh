#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VinylDesk"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Building $APP_NAME (Release)..."
cd "$ROOT_DIR"
swift build -c release --disable-sandbox

BIN_PATH="$(swift build -c release --disable-sandbox --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Binary not found at $BIN_PATH"
    exit 1
fi

echo "==> Packaging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/$APP_NAME"

# Generate a clean native vinyl app icon (.icns) directly in pure Swift (no iconutil dependency)
swift - "$RESOURCES_DIR/AppIcon.icns" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments[1]

func renderIconPNG(size: Int) -> Data? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Rounded macOS squircle background
    let inset = s * 0.08
    let bgRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = bgRect.width * 0.22
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let bgColors = [
        CGColor(colorSpace: colorSpace, components: [0.15, 0.15, 0.18, 1])!,
        CGColor(colorSpace: colorSpace, components: [0.06, 0.06, 0.08, 1])!
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }
    ctx.restoreGState()

    // Vinyl disc
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    let discR = s * 0.34
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.04, 0.04, 0.05, 1])!)
    ctx.fillEllipse(in: CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2))

    // Subtle concentric grooves
    ctx.setLineWidth(max(0.6, s * 0.0025))
    for i in 1...7 {
        let r = discR * (0.48 + CGFloat(i) * 0.068)
        let alpha: CGFloat = (i % 2 == 0) ? 0.15 : 0.07
        ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, alpha])!)
        ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    // Warm crimson/coral Apple-Music-inspired center label
    let labelR = discR * 0.38
    let labelRect = CGRect(x: center.x - labelR, y: center.y - labelR, width: labelR * 2, height: labelR * 2)
    ctx.saveGState()
    ctx.addEllipse(in: labelRect)
    ctx.clip()
    let labelColors = [
        CGColor(colorSpace: colorSpace, components: [0.98, 0.34, 0.42, 1])!,
        CGColor(colorSpace: colorSpace, components: [0.85, 0.16, 0.34, 1])!
    ] as CFArray
    if let labelGrad = CGGradient(colorsSpace: colorSpace, colors: labelColors, locations: [0, 1]) {
        ctx.drawLinearGradient(labelGrad, start: CGPoint(x: labelRect.minX, y: labelRect.maxY), end: CGPoint(x: labelRect.maxX, y: labelRect.minY), options: [])
    }
    ctx.restoreGState()

    // Center spindle hole
    let holeR = discR * 0.08
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.09, 0.09, 0.11, 1])!)
    ctx.fillEllipse(in: CGRect(x: center.x - holeR, y: center.y - holeR, width: holeR * 2, height: holeR * 2))

    guard let cgImage = ctx.makeImage() else { return nil }
    let mutableData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return mutableData as Data
}

// Standard macOS ICNS PNG chunk types
let chunks: [(String, Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512)
]

var body = Data()
for (code, px) in chunks {
    if let png = renderIconPNG(size: px) {
        body.append(contentsOf: code.utf8)
        var len = UInt32(png.count + 8).bigEndian
        body.append(Data(bytes: &len, count: 4))
        body.append(png)
    }
}

var icns = Data("icns".utf8)
var totalLen = UInt32(body.count + 8).bigEndian
icns.append(Data(bytes: &totalLen, count: 4))
icns.append(body)

try icns.write(to: URL(fileURLWithPath: outPath), options: .atomic)
SWIFT

echo "==> Ad-hoc signing $APP_BUNDLE..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Done! App bundle created at:"
echo "    $APP_BUNDLE"
