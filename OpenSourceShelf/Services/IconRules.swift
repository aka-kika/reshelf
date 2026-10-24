import Foundation
import CoreGraphics
import ImageIO

/// Pure parts of the icon download: the size math and the resize.
enum IconRules {
    /// The size that fits inside `maxSide` x `maxSide`, keeping the shape. Never scales up.
    static func fittedSize(width: Double, height: Double, maxSide: Double) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (0, 0) }
        // The smaller ratio, so the longer side lands on maxSide and the other fits inside.
        let ratio = min(1, min(maxSide / width, maxSide / height))
        return (max(1, Int((width * ratio).rounded())), max(1, Int((height * ratio).rounded())))
    }

    /// Returns PNG data that fits inside `maxSide` x `maxSide`, or nil when the data is not an image.
    /// Uses ImageIO and CGContext only, so it is safe to call off the main thread.
    static func resizedPNG(_ data: Data, maxSide: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let size = fittedSize(width: Double(image.width), height: Double(image.height), maxSide: maxSide)
        guard size.width > 0 else { return nil }
        guard let context = CGContext(data: nil, width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let scaled = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, scaled, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
