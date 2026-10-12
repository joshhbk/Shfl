import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import ShflAppleMusicUI

@Suite("Artwork pixels")
struct ArtworkPixelsTests {
    @Test("Reads a grid of colours from image data")
    func readsGrid() throws {
        let colors = try #require(ArtworkPixels.colors(in: try png(red: 255, green: 128, blue: 0), grid: 4))
        #expect(colors.count == 16)
        let first = colors[0].resolve(in: EnvironmentValues())
        #expect(abs(first.red - 1) < 0.02)
        #expect(abs(first.blue) < 0.02)
    }

    @Test("Data that isn't an image has no colours")
    func notAnImage() {
        #expect(ArtworkPixels.colors(in: Data("nope".utf8)) == nil)
    }

    private func png(red: UInt8, green: UInt8, blue: UInt8) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = red; pixels[i + 1] = green; pixels[i + 2] = blue; pixels[i + 3] = 255
        }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
            width: 16, height: 16, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 64, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
