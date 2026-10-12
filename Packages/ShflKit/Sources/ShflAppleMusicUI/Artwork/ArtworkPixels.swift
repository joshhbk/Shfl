import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Colours read from an artwork image itself, as a small grid of pixels.
nonisolated enum ArtworkPixels {
    static func colors(in data: Data, grid: Int = 8) -> [Color]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: grid * 4,
              ] as CFDictionary),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var pixels = [UInt8](repeating: 0, count: grid * grid * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: grid, height: grid, bitsPerComponent: 8, bytesPerRow: grid * 4,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: grid, height: grid))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 0, to: pixels.count, by: 4).map { i in
            Color(.sRGB, red: Double(pixels[i]) / 255, green: Double(pixels[i + 1]) / 255, blue: Double(pixels[i + 2]) / 255)
        }
    }
}
