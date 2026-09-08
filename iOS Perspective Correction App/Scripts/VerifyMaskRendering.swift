// Compile alongside CardProcessor.swift and Processing/*.swift; no API request is made.
import Foundation
import CoreImage
import ImageIO

@main struct VerifyMaskRendering {
    static func main() async throws {
        let processor = CardProcessor()
        let width = 200, height = 220
        let space = CGColorSpaceCreateDeviceRGB()
        for angle in [-0.3, 0.3] {
            var photo = [UInt8](repeating: 255, count: width * height * 4)
            var mask = photo
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Double(x - width / 2), dy = Double(y - height / 2)
                    let u = dx * cos(angle) + dy * sin(angle), v = -dx * sin(angle) + dy * cos(angle)
                    let inside = abs(u) < 45 && abs(v) < 75
                    let i = (y * width + x) * 4
                    photo[i] = inside ? 255 : 0; photo[i + 1] = 0; photo[i + 2] = inside ? 0 : 255
                    if inside && u < -15 && v < -35 { photo[i] = 0; photo[i + 1] = 255 }
                    for c in 0..<3 { mask[i + c] = inside ? 255 : 0 }
                }
            }
            func makeImage(_ bytes: [UInt8]) -> CGImage {
                CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                        space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            }
            let maskData = NSMutableData()
            let destination = CGImageDestinationCreateWithData(maskData, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, makeImage(mask), nil)
            precondition(CGImageDestinationFinalize(destination))
            let original = makeImage(photo)
            let result = try await processor.finish(original: original, image: CIImage(cgImage: original), maskData: maskData as Data)
            let scene = try await processor.sceneImage(result)
            var pixels = [UInt8](repeating: 0, count: photo.count)
            CIContext().render(CIImage(cgImage: scene), toBitmap: &pixels, rowBytes: width * 4,
                               bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: space)
            var lefts: [Int] = [], rights: [Int] = []
            for y in stride(from: 60, through: 160, by: 10) {
                let foreground = (0..<width).filter { x in
                    let i = (y * width + x) * 4
                    return pixels[i] > 200 || pixels[i + 1] > 200
                }
                precondition(!foreground.isEmpty)
                lefts.append(foreground.first!); rights.append(foreground.last!)
            }
            precondition(lefts.max()! - lefts.min()! <= 2 && rights.max()! - rights.min()! <= 2,
                         "Tilted card must become straight in the blur input, angle \(angle): \(lefts), \(rights)")
            let green = (0..<(width * height)).filter { pixels[$0 * 4 + 1] > 200 }
            precondition(!green.isEmpty && green.allSatisfy { $0 / width < height / 2 && $0 % width < width / 2 },
                         "Blur input must preserve the card's top-left orientation marker")
            print("PASS: tilted card \(angle) becomes straight and upright in full-scene blur input")
        }
        for alphaMask in [false, true] {
            var sourcePixels = [UInt8](repeating: 255, count: width * height * 4)
            var maskPixels = sourcePixels
            for y in 0..<height {
                for x in 0..<width {
                    let nx = max(57, min(x, 143)), ny = max(32, min(y, 162))
                    let inside = hypot(Double(x - nx), Double(y - ny)) <= 12
                    let i = (y * width + x) * 4
                    sourcePixels[i] = inside ? 255 : 0
                    sourcePixels[i + 1] = 0
                    sourcePixels[i + 2] = inside ? 0 : 255
                    if (60..<80).contains(x) && (40..<60).contains(y) {
                        sourcePixels[i] = 0; sourcePixels[i + 1] = 255
                    }
                    for c in 0..<3 { maskPixels[i + c] = inside ? 255 : 0 }
                    maskPixels[i + 3] = alphaMask ? (inside ? 255 : 0) : 255
                }
            }
            func image(_ bytes: [UInt8]) -> CGImage {
                CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                        space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            }
            let maskData = NSMutableData()
            let destination = CGImageDestinationCreateWithData(maskData, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image(maskPixels), nil)
            precondition(CGImageDestinationFinalize(destination))
            let original = image(sourcePixels)
            let result = try await processor.finish(original: original, image: CIImage(cgImage: original), maskData: maskData as Data)
            precondition(result.originalPreview.width < original.width && result.originalPreview.height < original.height,
                         "Original preview must be cropped to the padded mask bounds")
            let savedBefore = try await processor.originalPhotoData(result)
            let savedSource = CGImageSourceCreateWithData(savedBefore as CFData, nil)!
            let savedImage = CGImageSourceCreateImageAtIndex(savedSource, 0, nil)!
            precondition(savedImage.width == result.originalPreview.width && savedImage.height == result.originalPreview.height)
            let doubled = CIImage(cgImage: original).transformed(by: CGAffineTransform(scaleX: 2, y: 2))
            let fullResolution = CIContext().createCGImage(doubled, from: doubled.extent)!
            let sourceData = NSMutableData()
            let sourceDestination = CGImageDestinationCreateWithData(sourceData, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(sourceDestination, fullResolution, nil)
            precondition(CGImageDestinationFinalize(sourceDestination))
            var nativeResult = result
            nativeResult.originalData = sourceData as Data
            let nativeSaved = try await processor.originalPhotoData(nativeResult)
            let nativeSource = CGImageSourceCreateWithData(nativeSaved as CFData, nil)!
            let nativeImage = CGImageSourceCreateImageAtIndex(nativeSource, 0, nil)!
            precondition(abs(nativeImage.width - result.originalPreview.width * 2) <= 2 &&
                         abs(nativeImage.height - result.originalPreview.height * 2) <= 2,
                         "Saving the cropped original must retain native resolution")
            for turns in 0..<4 {
                let r = try await processor.render(result, aspectRatio: turns % 2 == 0 ? result.aspectRatio : 1 / result.aspectRatio, quarterTurns: turns)
                let fullScene = try await processor.sceneImage(r)
                let cropped = try await processor.cropBlurredImage(fullScene, result: r)
                precondition(cropped.image.width < fullScene.width && cropped.image.height < fullScene.height)
                let expectedWidth = turns % 2 == 0 ? 126 : 170
                let expectedHeight = turns % 2 == 0 ? 170 : 126
                precondition(abs(cropped.image.width - expectedWidth) <= 3 && abs(cropped.image.height - expectedHeight) <= 3,
                             "Padded blur crop must follow rotation, got \(cropped.image.width)x\(cropped.image.height)")
            }
            let decoded = CGImageSourceCreateWithData(result.pngData as CFData, nil)!
            let png = CGImageSourceCreateImageAtIndex(decoded, 0, nil)!
            let w = png.width, h = png.height
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            CIContext().render(CIImage(cgImage: png), toBitmap: &bytes, rowBytes: w * 4,
                    bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: space)
            let cornerAlpha = [3, (w - 1) * 4 + 3, ((h - 1) * w) * 4 + 3, (h * w - 1) * 4 + 3].map { bytes[$0] }
            precondition(cornerAlpha.allSatisfy { $0 < 10 }, "Rounded corner background must be transparent")
            let center = ((h / 2) * w + w / 2) * 4
            precondition(bytes[center + 3] > 250 && bytes[center] > 250, "Card content must remain opaque and red: \(Array(bytes[center..<(center + 4)]))")
            precondition(abs(Double(h) / Double(w) - 1.4) < 0.02, "Card aspect ratio must be preserved")
            let custom = try await processor.render(result, aspectRatio: 0.6)
            precondition(abs(Double(custom.corrected.width) / Double(custom.corrected.height) - 0.6) < 0.01,
                         "Custom proportions must control output dimensions")
            let rotated = try await processor.render(result, aspectRatio: 1 / result.aspectRatio, quarterTurns: 1)
            precondition(rotated.corrected.width == result.corrected.height && rotated.corrected.height == result.corrected.width,
                         "Rotation must swap dimensions without stretching the card")
            func greenCenter(_ image: CGImage) -> CGPoint {
                var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                CIContext().render(CIImage(cgImage: image), toBitmap: &pixels, rowBytes: image.width * 4,
                                   bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height), format: .RGBA8, colorSpace: space)
                var x = 0.0, y = 0.0, count = 0.0
                for index in 0..<(image.width * image.height) where pixels[index * 4 + 1] > 200 && pixels[index * 4] < 50 {
                    x += Double(index % image.width); y += Double(index / image.width); count += 1
                }
                precondition(count > 0, "Orientation marker must survive export")
                return CGPoint(x: x / count, y: y / count)
            }
            let before = greenCenter(result.corrected), after = greenCenter(rotated.corrected)
            precondition(abs(after.x - (Double(result.corrected.height - 1) - before.y)) < 2 && abs(after.y - before.x) < 2,
                         "Rotate must turn pixels clockwise, not just swap dimensions")
            let scene = try await processor.sceneImage(result)
            let rotatedScene = try await processor.sceneImage(rotated)
            precondition(scene.width == width && scene.height == height, "Blur input must retain the original photo canvas")
            precondition(rotatedScene.width == height && rotatedScene.height == width, "Blur scene rotation must match the card")
            let sceneMarker = greenCenter(scene), originalMarker = greenCenter(original), rotatedMarker = greenCenter(rotatedScene)
            precondition(abs(sceneMarker.x - originalMarker.x) < 3 && abs(sceneMarker.y - originalMarker.y) < 3,
                         "Full-scene warp must preserve marker orientation for a frontal card: \(sceneMarker), \(originalMarker)")
            precondition(abs(rotatedMarker.x - (Double(height - 1) - sceneMarker.y)) < 2 && abs(rotatedMarker.y - sceneMarker.x) < 2,
                         "Blur scene must rotate clockwise")
            var sceneBytes = [UInt8](repeating: 0, count: width * height * 4)
            CIContext().render(CIImage(cgImage: scene), toBitmap: &sceneBytes, rowBytes: width * 4,
                               bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: space)
            let background = (10 * width + 10) * 4
            precondition(sceneBytes[background + 2] > 250 && sceneBytes[background + 3] > 250,
                         "Blur input must keep the original blue background")
            let restored = try await processor.render(result, aspectRatio: result.aspectRatio, quarterTurns: 4)
            precondition(restored.corrected.width == result.corrected.width && restored.corrected.height == result.corrected.height,
                         "Four turns must restore original dimensions")
            print("PASS: \(alphaMask ? "alpha" : "grayscale") mask, transparent PNG corners, opaque card, correct ratio (\(w)x\(h))")
        }
    }
}
