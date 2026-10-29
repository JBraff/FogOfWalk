import CoreGraphics

// The buffer stores rows bottom-up; pixelColor accepts top-left image coordinates.
/// Allocates an RGBA buffer and draws `image` into it once, for scanning multiple pixels
/// without re-drawing the whole image per lookup.
func pixelBuffer(for image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    let bpp = 4, bpr = w * bpp
    var data = [UInt8](repeating: 0, count: h * bpr)

    guard let ctx = CGContext(
        data: &data, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: bpr,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return data }

    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return data
}

/// Reads the RGBA of a single pixel from a pre-drawn buffer.
func pixelColor(at point: CGPoint, in buffer: [UInt8], width: Int, height: Int)
    -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
{
    let x = Int(point.x.rounded()), y = Int(point.y.rounded())
    guard x >= 0, x < width, y >= 0, y < height else { return (0, 0, 0, 0) }

    let bpp = 4, bpr = width * bpp
    let offset = (height - 1 - y) * bpr + x * bpp
    return (buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3])
}


/// Reads the RGBA of a single pixel from a CGImage.
func pixelColor(at point: CGPoint, in image: CGImage)
    -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
{
    let w = image.width, h = image.height
    let x = Int(point.x.rounded()), y = Int(point.y.rounded())
    guard x >= 0, x < w, y >= 0, y < h else { return (0, 0, 0, 0) }

    let buffer = pixelBuffer(for: image)
    return pixelColor(at: point, in: buffer, width: w, height: h)
}
