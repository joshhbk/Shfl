import SwiftUI
import UIKit

/// Extracts dominant colors from album artwork for dynamic UI theming
@MainActor
final class AlbumArtColorExtractor: ObservableObject {
    @Published private(set) var extractedColor: Color?
    @Published private(set) var isLoading: Bool = false

    private var colorCache: [String: Color] = [:]
    private var currentSongId: String?
    private var currentTask: Task<Void, Never>?

    /// Extracts the dominant vibrant color from the artwork at the given URL
    /// - Parameters:
    ///   - url: The URL of the album artwork
    ///   - songId: Unique identifier for caching
    func extractColor(from url: URL?, songId: String) {
        // Skip if already processing this song
        guard songId != currentSongId else { return }
        currentSongId = songId

        // Check cache first
        if let cached = colorCache[songId] {
            withAnimation(.easeInOut(duration: 0.5)) {
                extractedColor = cached
            }
            return
        }

        // Cancel any existing task
        currentTask?.cancel()

        guard let url = url else {
            withAnimation(.easeInOut(duration: 0.5)) {
                extractedColor = nil
            }
            return
        }

        isLoading = true

        currentTask = Task {
            do {
                let color = try await downloadAndExtract(from: url)

                guard !Task.isCancelled else { return }

                // Cache the result
                colorCache[songId] = color

                withAnimation(.easeInOut(duration: 0.5)) {
                    extractedColor = color
                    isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: 0.5)) {
                    extractedColor = nil
                    isLoading = false
                }
            }
        }
    }

    /// Clears the extracted color (used when playback stops)
    func clear() {
        currentTask?.cancel()
        currentSongId = nil
        withAnimation(.easeInOut(duration: 0.5)) {
            extractedColor = nil
            isLoading = false
        }
    }

    // MARK: - Private

    private func downloadAndExtract(from url: URL) async throws -> Color {
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let image = UIImage(data: data) else {
            throw ColorExtractionError.invalidImageData
        }

        return try await extractDominantColor(from: image)
    }

    private func extractDominantColor(from image: UIImage) async throws -> Color {
        guard let cgImage = image.cgImage else {
            throw ColorExtractionError.invalidImageData
        }

        // Downsample for performance
        let sampleSize = 50
        let width = sampleSize
        let height = sampleSize

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4 * width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ColorExtractionError.contextCreationFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Collect colors with their vibrancy scores
        var colorScores: [(color: (r: CGFloat, g: CGFloat, b: CGFloat), score: CGFloat)] = []

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let b = CGFloat(pixelData[offset + 2]) / 255.0
                let a = CGFloat(pixelData[offset + 3]) / 255.0

                // Skip transparent/near-transparent pixels
                guard a > 0.5 else { continue }

                let (_, saturation, brightness) = rgbToHSB(r: r, g: g, b: b)

                // Calculate vibrancy score - prefer saturated, mid-brightness colors
                // Penalize very dark or very light colors
                let brightnessPenalty = abs(brightness - 0.6) * 0.5
                let vibrancy = saturation * (1.0 - brightnessPenalty)

                // Only consider reasonably vibrant colors
                if vibrancy > 0.15 {
                    colorScores.append((color: (r, g, b), score: vibrancy))
                }
            }
        }

        // If no vibrant colors found, use average color
        if colorScores.isEmpty {
            let avgColor = calculateAverageColor(from: pixelData, width: width, height: height)
            return boostColorIfNeeded(avgColor)
        }

        // Sort by vibrancy and take top colors
        colorScores.sort { $0.score > $1.score }
        let topColors = colorScores.prefix(100)

        // Average the top vibrant colors
        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var totalWeight: CGFloat = 0

        for item in topColors {
            let weight = item.score
            totalR += item.color.r * weight
            totalG += item.color.g * weight
            totalB += item.color.b * weight
            totalWeight += weight
        }

        let avgR = totalR / totalWeight
        let avgG = totalG / totalWeight
        let avgB = totalB / totalWeight

        return boostColorIfNeeded(Color(red: avgR, green: avgG, blue: avgB))
    }

    private func calculateAverageColor(from pixelData: [UInt8], width: Int, height: Int) -> Color {
        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let a = CGFloat(pixelData[offset + 3]) / 255.0
                guard a > 0.5 else { continue }

                totalR += CGFloat(pixelData[offset]) / 255.0
                totalG += CGFloat(pixelData[offset + 1]) / 255.0
                totalB += CGFloat(pixelData[offset + 2]) / 255.0
                count += 1
            }
        }

        guard count > 0 else {
            return .white
        }

        return Color(red: totalR / count, green: totalG / count, blue: totalB / count)
    }

    /// Boosts saturation and brightness if the color is too dark or desaturated
    private func boostColorIfNeeded(_ color: Color) -> Color {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Boost saturation if too low
        let minSaturation: CGFloat = 0.4
        let boostedSaturation = max(saturation, minSaturation)

        // Boost brightness if too dark, but don't make it too bright
        let minBrightness: CGFloat = 0.5
        let maxBrightness: CGFloat = 0.9
        let boostedBrightness = min(max(brightness, minBrightness), maxBrightness)

        return Color(hue: hue, saturation: boostedSaturation, brightness: boostedBrightness)
    }

    // MARK: - Color Space Conversion

    private func rgbToHSB(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal

        // Brightness
        let brightness = maxVal

        // Saturation
        let saturation = maxVal == 0 ? 0 : delta / maxVal

        // Hue
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
}

// MARK: - Errors

enum ColorExtractionError: Error {
    case invalidImageData
    case contextCreationFailed
}
