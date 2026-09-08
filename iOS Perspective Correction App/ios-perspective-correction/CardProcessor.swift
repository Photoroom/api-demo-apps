import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision


struct CardResult: Sendable {
    let original: CGImage
    let corrected: CGImage
    let detection: CardDetection
    let pngData: Data
    let cutout: CIImage
    let automaticRatio: AspectRatioEstimate?
    let aspectRatio: Double
    let quarterTurns: Int
    var originalData: Data? = nil
    var framedOriginal: CGImage? = nil
    var originalPreview: CGImage { framedOriginal ?? original }
}

struct FinishedCard: Sendable { let image: CGImage; let data: Data }

// Serial actor keeps image decoding, mask traversal, and rendering off the UI actor.
actor CardProcessor {
    private let context = CIContext()

    private let photoroom = PhotoroomClient()

    func process(_ data: Data, apiKey: String, calibration: CameraCalibration? = nil) async throws -> CardResult {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3000
              ] as CFDictionary) else { throw CardError.invalidImage }
        let image = CIImage(cgImage: original)
        let upload = try encode(original, type: "public.jpeg", properties: [kCGImageDestinationLossyCompressionQuality: 0.98])
        let maskData = try await photoroom.segmentationMask(image: upload, apiKey: apiKey)
        try Task.checkCancellation()
        var result = try finish(original: original, image: image, maskData: maskData, calibration: calibration)
        result.originalData = data
        return try orientContent(result)
    }

    // Kept separate from the HTTP request so mask alignment and transparency can be regression-tested.
    func finish(original: CGImage, image: CIImage, maskData: Data, calibration: CameraCalibration? = nil) throws -> CardResult {
        guard let maskSource = CGImageSourceCreateWithData(maskData as CFData, nil),
              let maskCG = CGImageSourceCreateImageAtIndex(maskSource, 0, nil) else { throw PhotoroomError.invalidResponse }
        let fullMask = CIImage(cgImage: maskCG)
        let scale = min(1, 1600 / max(fullMask.extent.width, fullMask.extent.height))
        let w = max(1, Int((fullMask.extent.width * scale).rounded()))
        let h = max(1, Int((fullMask.extent.height * scale).rounded()))
        let analysisMask = fullMask.transformed(by: CGAffineTransform(scaleX: Double(w) / fullMask.extent.width, y: Double(h) / fullMask.extent.height))
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        context.render(analysisMask, toBitmap: &rgba, rowBytes: w * 4,
                       bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        // Like the demo, accept either variable alpha or an opaque grayscale mask.
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        let usesAlpha = Int(alpha.max() ?? 0) - Int(alpha.min() ?? 0) > 30
        let binary: [UInt8] = (0..<(w * h)).map { i in
            if usesAlpha { return alpha[i] > 80 ? 1 : 0 }
            let j = i * 4
            let luminance = Double(rgba[j]) * 0.2126 + Double(rgba[j + 1]) * 0.7152 + Double(rgba[j + 2]) * 0.0722
            return luminance > 30 ? 1 : 0
        }
        let detection = try CardGeometry.detect(mask: binary, width: w, height: h,
                                                sourceWidth: original.width, sourceHeight: original.height)
        let compositingMask = fullMask.transformed(by: CGAffineTransform(
            scaleX: image.extent.width / fullMask.extent.width,
            y: image.extent.height / fullMask.extent.height))
        // Alpha masks must use their alpha channel directly, not their RGB values.
        let cutout = image.applyingFilter(usesAlpha ? "CIBlendWithAlphaMask" : "CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent),
            kCIInputMaskImageKey: compositingMask
        ]).cropped(to: image.extent)
        try Task.checkCancellation()
        // Warp the color and its alpha together, retaining soft/rounded corners.
        let estimate = calibration.flatMap {
            AspectRatioEstimator.estimate(corners: detection.corners, calibration: $0,
                                          imageWidth: Double(original.width), imageHeight: Double(original.height))
        }
        let p = detection.corners
        // Without calibration this is only a provisional preview, never an automatic estimate.
        let previewRatio = max(p[0].distance(to: p[1]), p[2].distance(to: p[3])) /
                           max(p[0].distance(to: p[3]), p[1].distance(to: p[2]))
        let ratio = estimate?.widthOverHeight ?? previewRatio
        let corrected = try rectify(cutout, detection: detection, aspectRatio: ratio)
        let png = try encode(corrected, type: "public.png")
        let crop = CardGeometry.paddedItemCrop(bounds: detection.maskBounds ?? CardGeometry.bounds(of: detection.corners),
                                               canvas: CGSize(width: original.width, height: original.height))
        guard let framed = original.cropping(to: crop) else { throw CardError.exportFailed }
        return CardResult(original: original, corrected: corrected, detection: detection, pngData: png,
                          cutout: cutout, automaticRatio: estimate, aspectRatio: ratio, quarterTurns: 0, framedOriginal: framed)
    }

    // A quadrilateral has no semantic top. Text can disambiguate a sideways/upside-down card
    // without forcing portrait proportions or making another Photoroom request.
    func uprightQuarterTurns(_ image: CGImage) throws -> Int {
        let scale = min(1, 1200 / Double(max(image.width, image.height)))
        let reduced = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let sample = context.createCGImage(reduced, from: reduced.extent) else { return 0 }
        var scores = [Double](repeating: 0, count: 4)
        for turn in 0..<4 {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = ["en-US", "ja-JP", "fr-FR", "de-DE", "es-ES", "it-IT"].filter { supported.contains($0) }
            do {
                try VNImageRequestHandler(cgImage: sample, orientation: [.up, .right, .down, .left][turn]).perform([request])
                scores[turn] = (request.results ?? []).reduce(0) { sum, observation in
                    guard let text = observation.topCandidates(1).first, text.confidence >= 0.65 else { return sum }
                    let count = text.string.filter { $0.isLetter || $0.isNumber }.count
                    guard count >= 3 else { return sum }
                    // Vision can read sideways text too. Score only baselines that read
                    // left-to-right in this candidate orientation, not recognition alone.
                    guard let box = try? text.boundingBox(for: text.string.startIndex..<text.string.endIndex) else { return sum }
                    let dx = box.topRight.x - box.topLeft.x, dy = box.topRight.y - box.topLeft.y
                    guard dx > 0, abs(dy) < dx * 0.25 else { return sum }
                    return sum + Double(min(count, 40)) * Double(text.confidence)
                }
            } catch { return 0 } // Unreadable/unsupported text must never make correction fail.
        }
        let ranked = scores.indices.sorted { scores[$0] > scores[$1] }
        let best = ranked[0], runnerUp = scores[ranked[1]]
        guard scores[best] >= 12, scores[best] >= runnerUp * 1.3 + 3 else { return 0 }
        return best
    }

    func orientContent(_ result: CardResult) throws -> CardResult {
        let turns = try uprightQuarterTurns(result.corrected)
        guard turns != 0 else { return result }
        let rotated = CIImage(cgImage: result.corrected).oriented([.up, .right, .down, .left][turns])
        guard let image = context.createCGImage(rotated, from: rotated.extent) else { throw CardError.exportFailed }
        let corners = (0..<4).map { result.detection.corners[($0 - turns + 4) % 4] }
        let estimate = result.automaticRatio.map {
            AspectRatioEstimate(widthOverHeight: turns % 2 == 0 ? $0.widthOverHeight : 1 / $0.widthOverHeight,
                                relativeUncertainty: $0.relativeUncertainty)
        }
        return CardResult(original: result.original, corrected: image,
                          detection: CardDetection(corners: corners, confidence: result.detection.confidence, maskBounds: result.detection.maskBounds),
                          pngData: try encode(image, type: "public.png"), cutout: result.cutout,
                          automaticRatio: estimate, aspectRatio: turns % 2 == 0 ? result.aspectRatio : 1 / result.aspectRatio,
                          quarterTurns: 0, originalData: result.originalData, framedOriginal: result.framedOriginal)
    }

    /// Proportion changes reuse the mask and pixels; they never incur another API request.
    func render(_ result: CardResult, aspectRatio: Double, quarterTurns: Int = 0) throws -> CardResult {
        let turns = (quarterTurns % 4 + 4) % 4
        let sourceRatio = turns % 2 == 0 ? aspectRatio : 1 / aspectRatio
        let rectified = try rectify(result.cutout, detection: result.detection, aspectRatio: sourceRatio)
        let orientation: CGImagePropertyOrientation = [.up, .right, .down, .left][turns]
        let rotated = CIImage(cgImage: rectified).oriented(orientation)
        guard let corrected = context.createCGImage(rotated, from: rotated.extent) else { throw CardError.exportFailed }
        let png = try encode(corrected, type: "public.png")
        return CardResult(original: result.original, corrected: corrected, detection: result.detection, pngData: png,
                          cutout: result.cutout, automaticRatio: result.automaticRatio, aspectRatio: aspectRatio, quarterTurns: turns, originalData: result.originalData, framedOriginal: result.framedOriginal)
    }

    func blurredFinish(_ result: CardResult, apiKey: String, relight: Bool = true) async throws -> FinishedCard {
        let scene = try sceneImage(result)
        let data = try await photoroom.blurredFinish(image: encode(scene, type: "public.png"), apiKey: apiKey, relight: relight)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PhotoroomError.invalidResponse }
        return try cropBlurredImage(image, result: result)
    }

    func cropBlurredImage(_ image: CGImage, result: CardResult) throws -> FinishedCard {
        // The full scene is still expanded/blurred exactly as before. Map the mask-derived
        // rectified item into the returned originalImage canvas, then crop the final JPEG.
        let w = Double(result.original.width), h = Double(result.original.height)
        let turns = result.quarterTurns
        let ratio = turns % 2 == 0 ? result.aspectRatio : 1 / result.aspectRatio
        let points = try CardGeometry.sceneDestination(corners: result.detection.corners, width: w, height: h, aspectRatio: ratio)
        let rotated = points.map { p -> CardPoint in
            switch turns {
            case 1: return CardPoint(x: h - p.y, y: p.x)
            case 2: return CardPoint(x: w - p.x, y: h - p.y)
            case 3: return CardPoint(x: p.y, y: w - p.x)
            default: return p
            }
        }
        let canvasWidth = turns % 2 == 0 ? w : h, canvasHeight = turns % 2 == 0 ? h : w
        let scaled = rotated.map { CardPoint(x: $0.x * Double(image.width) / canvasWidth,
                                             y: $0.y * Double(image.height) / canvasHeight) }
        let crop = CardGeometry.paddedItemCrop(bounds: CardGeometry.bounds(of: scaled), canvas: CGSize(width: image.width, height: image.height))
        guard let cropped = image.cropping(to: crop) else { throw CardError.exportFailed }
        return FinishedCard(image: cropped, data: try encode(cropped, type: "public.jpeg", properties: [kCGImageDestinationLossyCompressionQuality: 0.98]))
    }

    // The demo warps the whole photograph, leaving transparent borders for AI Expand.
    // Keep that background context for blur, while the default export remains the masked cutout.
    func sceneImage(_ result: CardResult) throws -> CGImage {
        let width = result.original.width, height = result.original.height
        let p = result.detection.corners
        let ratio = result.quarterTurns % 2 == 0 ? result.aspectRatio : 1 / result.aspectRatio
        let destination = try CardGeometry.sceneDestination(corners: p, width: Double(width), height: Double(height), aspectRatio: ratio)
        var rows: [[Double]] = []
        for (a, b) in zip(destination, p) {
            rows.append([a.x, a.y, 1, 0, 0, 0, -b.x * a.x, -b.x * a.y, b.x])
            rows.append([0, 0, 0, a.x, a.y, 1, -b.y * a.x, -b.y * a.y, b.y])
        }
        for column in 0..<8 {
            let pivot = (column..<8).max { abs(rows[$0][column]) < abs(rows[$1][column]) }!
            guard abs(rows[pivot][column]) > 1e-10 else { throw CardError.exportFailed }
            rows.swapAt(column, pivot)
            let divisor = rows[column][column]
            for k in column...8 { rows[column][k] /= divisor }
            for row in 0..<8 where row != column {
                let factor = rows[row][column]
                for k in column...8 { rows[row][k] -= factor * rows[column][k] }
            }
        }
        let m = rows.map { $0[8] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let bitmap = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CardError.exportFailed }
            // Raw bitmap rows already match the detector’s top-left coordinates.
            // A UIKit-style Y flip here would invert pixels without moving the corners.
            bitmap.draw(result.original, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var output = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height {
            if y % 64 == 0 { try Task.checkCancellation() }
            for x in 0..<width {
                let denominator = m[6] * Double(x) + m[7] * Double(y) + 1
                let sx = (m[0] * Double(x) + m[1] * Double(y) + m[2]) / denominator
                let sy = (m[3] * Double(x) + m[4] * Double(y) + m[5]) / denominator
                guard sx.isFinite, sy.isFinite, sx >= 0, sy >= 0, sx < Double(width - 1), sy < Double(height - 1) else { continue }
                let left = Int(sx), top = Int(sy), dx = sx - Double(Int(sx)), dy = sy - Double(Int(sy))
                for c in 0..<4 {
                    let a = Double(pixels[(top * width + left) * 4 + c]) * (1 - dx) + Double(pixels[(top * width + left + 1) * 4 + c]) * dx
                    let b = Double(pixels[((top + 1) * width + left) * 4 + c]) * (1 - dx) + Double(pixels[((top + 1) * width + left + 1) * 4 + c]) * dx
                    output[(y * width + x) * 4 + c] = UInt8(clamping: Int((a * (1 - dy) + b * dy).rounded()))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CardError.exportFailed }
        let rotated = CIImage(cgImage: image).oriented([.up, .right, .down, .left][result.quarterTurns])
        guard let scene = context.createCGImage(rotated, from: rotated.extent) else { throw CardError.exportFailed }
        return scene
    }

    func originalPhotoData(_ result: CardResult) throws -> Data {
        // Crop the original at its native resolution when source bytes are available.
        if let data = result.originalData, let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           let original = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height)
           ] as CFDictionary) {
            let bounds = result.detection.maskBounds ?? CardGeometry.bounds(of: result.detection.corners)
            let scaled = bounds.applying(CGAffineTransform(scaleX: Double(original.width) / Double(result.original.width),
                                                          y: Double(original.height) / Double(result.original.height)))
            let crop = CardGeometry.paddedItemCrop(bounds: scaled, canvas: CGSize(width: original.width, height: original.height))
            guard let image = original.cropping(to: crop) else { throw CardError.exportFailed }
            return try encode(image, type: "public.jpeg", properties: [kCGImageDestinationLossyCompressionQuality: 0.98])
        }
        return try encode(result.originalPreview, type: "public.png")
    }

    private func encode(_ image: CGImage, type: String, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { throw CardError.exportFailed }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CardError.exportFailed }
        return data as Data
    }

    private func rectify(_ image: CIImage, detection: CardDetection, aspectRatio: Double) throws -> CGImage {
        let p = detection.corners
        guard aspectRatio.isFinite, (0.2...5).contains(aspectRatio) else { throw CardError.exportFailed }
        guard CardGeometry.valid(p), p.allSatisfy({ $0.x >= 0 && $0.y >= 0 && $0.x <= image.extent.width && $0.y <= image.extent.height }) else { throw CardError.noCard }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        func ciPoint(_ p: CardPoint) -> CGPoint { CGPoint(x: p.x, y: image.extent.height - p.y) }
        filter.topLeft = ciPoint(p[0]); filter.topRight = ciPoint(p[1])
        filter.bottomRight = ciPoint(p[2]); filter.bottomLeft = ciPoint(p[3])
        guard let rectified = filter.outputImage else { throw CardError.exportFailed }
        // Preserve measured area, but let calibration or the user supply W/H.
        let measuredWidth = max(p[0].distance(to: p[1]), p[2].distance(to: p[3]))
        let measuredHeight = max(p[0].distance(to: p[3]), p[1].distance(to: p[2]))
        let width = sqrt(measuredWidth * measuredHeight * aspectRatio)
        let height = width / aspectRatio
        let fit = min(1, 2400 / max(width, height))
        let size = CGSize(width: width * fit, height: height * fit)
        let normalized = rectified.transformed(by: CGAffineTransform(translationX: -rectified.extent.minX, y: -rectified.extent.minY))
        let output = normalized.transformed(by: CGAffineTransform(scaleX: size.width / normalized.extent.width, y: size.height / normalized.extent.height))
        guard let result = context.createCGImage(output, from: CGRect(origin: .zero, size: size).integral) else { throw CardError.exportFailed }
        return result
    }
}
