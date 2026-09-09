#if DEBUG
import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Deterministic UI fixture for Simulator checks; never contacts Photoroom or reads credentials.
enum ProportionPreviewFixture {
    static func make(calibrated: Bool, tilted: Bool = false) async throws -> CardResult {
        let width = 600, height = 800
        let rect = CGRect(x: 180, y: 190, width: 240, height: 420)
        func draw(mask: Bool) throws -> CGImage {
            guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CardError.invalidImage }
            canvas.setFillColor(CGColor(gray: mask ? 0 : 0.8, alpha: 1))
            canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if tilted {
                canvas.translateBy(x: 300, y: 400)
                canvas.rotate(by: 0.3)
                canvas.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.18, d: 0.85, tx: 0, ty: 0))
                canvas.translateBy(x: -300, y: -400)
            }
            canvas.setFillColor(mask ? CGColor(gray: 1, alpha: 1) : CGColor(red: 0.3, green: 0.2, blue: 0.9, alpha: 1))
            canvas.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil))
            canvas.fillPath()
            if !mask {
                canvas.setFillColor(CGColor(gray: 1, alpha: 0.9))
                canvas.fill(CGRect(x: 204, y: 220, width: 192, height: 250))
                canvas.fill(CGRect(x: 204, y: 510, width: 150, height: 12))
                canvas.fill(CGRect(x: 204, y: 548, width: 110, height: 12))
            }
            guard let image = canvas.makeImage() else { throw CardError.invalidImage }
            return image
        }
        let source = try draw(mask: false)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw CardError.exportFailed }
        CGImageDestinationAddImage(destination, try draw(mask: true), nil)
        guard CGImageDestinationFinalize(destination) else { throw CardError.exportFailed }
        let calibration = calibrated ? CameraCalibration(focalX: 900, focalY: 900, centerX: 300, centerY: 400,
                                                         width: 600, height: 800, orientation: 1) : nil
        return try await CardProcessor().finish(original: source, image: CIImage(cgImage: source), maskData: data as Data, calibration: calibration)
    }
}
#endif
