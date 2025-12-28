import Combine
import SwiftUI
import UIKit

/// Extracts dominant colors from album artwork by analyzing the image
@MainActor
final class AlbumArtColorExtractor: ObservableObject {
    @Published private(set) var extractedColor: Color?

    private var currentSongId: String?
    private var currentTask: Task<Void, Never>?
    private var colorCache: [String: Color] = [:]

    /// Updates the extracted color for the given song
    func updateColor(for songId: String, artworkURL: URL?) {
        // Skip if already processing this song
        guard songId != currentSongId else {
            print("[ColorExtractor] Skipping - already processing songId: \(songId)")
            return
        }
        currentSongId = songId

        // Check cache first
        if let cached = colorCache[songId] {
            print("[ColorExtractor] Using cached color for songId: \(songId)")
            withAnimation(.easeInOut(duration: 0.5)) {
                extractedColor = cached
            }
            return
        }

        // Cancel any existing task
        currentTask?.cancel()

        guard let url = artworkURL else {
            print("[ColorExtractor] No artworkURL available for songId: \(songId)")
            return
        }

        print("[ColorExtractor] Downloading image for songId: \(songId)")
        currentTask = Task {
            do {
                let color = try await extractColorFromImage(url: url)
                guard !Task.isCancelled, currentSongId == songId else { return }

                colorCache[songId] = color
                let uiColor = UIColor(color)
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
                uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
                print("[ColorExtractor] Extracted color - hue: \(h), sat: \(s), bright: \(b)")
                withAnimation(.easeInOut(duration: 0.5)) {
                    extractedColor = color
                }
            } catch {
                print("[ColorExtractor] Failed to extract color: \(error)")
            }
        }
    }

    /// Clears the extracted color (used when playback stops)
    func clear() {
        currentTask?.cancel()
        currentSongId = nil
        withAnimation(.easeInOut(duration: 0.5)) {
            extractedColor = nil
        }
    }

    // MARK: - Image-based extraction

    private func extractColorFromImage(url: URL) async throws -> Color {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw ColorExtractionError.invalidImageData
        }

        // Downsample for performance
        let sampleSize = 50
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)

        guard let context = CGContext(
            data: &pixelData,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: 4 * sampleSize,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ColorExtractionError.contextCreationFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        // Find the most vibrant color
        var bestColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.5, 0.5, 0.5)
        var bestVibrancy: CGFloat = 0

        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let offset = (y * sampleSize + x) * 4
                let r = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let b = CGFloat(pixelData[offset + 2]) / 255.0
                let a = CGFloat(pixelData[offset + 3]) / 255.0

                guard a > 0.5 else { continue }

                let (_, saturation, brightness) = rgbToHSB(r: r, g: g, b: b)
                // Prefer saturated colors with mid-range brightness
                let vibrancy = saturation * (1.0 - abs(brightness - 0.6) * 0.5)

                if vibrancy > bestVibrancy {
                    bestVibrancy = vibrancy
                    bestColor = (r, g, b)
                }
            }
        }

        return boostColorIfNeeded(Color(red: bestColor.r, green: bestColor.g, blue: bestColor.b))
    }

    private func rgbToHSB(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal

        let brightness = maxVal
        let saturation = maxVal == 0 ? 0 : delta / maxVal

        var hue: CGFloat = 0
        if delta != 0 {
            if maxVal == r {
                hue = (g - b) / delta + (g < b ? 6 : 0)
            } else if maxVal == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
        }

        return (hue, saturation, brightness)
    }

    // MARK: - Color adjustment

    private func boostColorIfNeeded(_ color: Color) -> Color {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Boost saturation for visibility
        let boostedSaturation = max(saturation, 0.5)

        // Ensure good brightness range
        let boostedBrightness = min(max(brightness, 0.6), 0.95)

        return Color(hue: hue, saturation: boostedSaturation, brightness: boostedBrightness)
    }
}

private enum ColorExtractionError: Error {
    case invalidImageData
    case contextCreationFailed
}
