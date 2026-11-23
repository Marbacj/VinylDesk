import AppKit
import CoreImage
import SwiftUI

public enum ColorExtractor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Extracts an aesthetically pleasing ambient tint color from album artwork.
    public static func extractAmbientColor(from image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let ciImage = CIImage(bitmapImageRep: bitmap) else {
            return nil
        }

        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        // Sample the central 70% to avoid white/black borders on some album covers.
        let insetRect = extent.insetBy(dx: extent.width * 0.15, dy: extent.height * 0.15)
        let sampleExtent = insetRect.isEmpty ? extent : insetRect

        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: sampleExtent)
            ]
        ),
        let output = filter.outputImage else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let red = CGFloat(pixel[0]) / 255.0
        let green = CGFloat(pixel[1]) / 255.0
        let blue = CGFloat(pixel[2]) / 255.0

        let rawColor = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rawColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Slightly boost muted colors while keeping greys tasteful.
        let boostedSaturation: CGFloat = saturation > 0.08 ? min(max(saturation * 1.25, 0.30), 0.78) : saturation
        let balancedBrightness: CGFloat = min(max(brightness, 0.42), 0.82)

        return NSColor(
            hue: hue,
            saturation: boostedSaturation,
            brightness: balancedBrightness,
            alpha: 1.0
        )
    }
}
