import Foundation

/// Require two sharp observations after a short aiming period, without a continuous-stillness requirement.
struct AutoCaptureGate {
    enum Status: String, Sendable {
        case searching = "Show the whole card"
        case focusing = "Focusing…"
        case light = "Add more light"
        case soft = "Looking for a sharper frame…"
        case holding = "Card found — getting ready…"
        case capture = "Capturing…"
    }
    private var firstSeen: Double?
    private var lastSeen: Double?
    private var sharpSince: Double?
    private var fired = false

    mutating func reset() { self = Self() }

    mutating func assess(time: Double, corners: [CardPoint]?, sharpness: Double,
                         brightness: Double, adjusting: Bool) -> Status {
        guard !fired else { return .capture }
        guard time.isFinite else { reset(); return .searching }
        if let lastSeen, time < lastSeen || time - lastSeen > 0.8 { reset() }
        guard let corners, corners.count == 4 else { sharpSince = nil; return .searching }
        if firstSeen == nil { firstSeen = time }
        lastSeen = time
        let elapsed = time - firstSeen!
        // Give the user a brief chance to aim, but do not restart for hand tremor,
        // pixel changes, a soft frame, or an isolated missed rectangle detection.
        guard elapsed >= 0.6 else { return .holding }
        guard brightness.isFinite, brightness >= 0.08 else { sharpSince = nil; return .light }
        guard sharpness.isFinite, sharpness >= 80 else { sharpSince = nil; return .soft }
        // Continuous autofocus may report adjusting even when the image is sharp.
        // Wait briefly, then trust measured detail rather than blocking indefinitely.
        guard !adjusting || elapsed >= 1.2 else { sharpSince = nil; return .focusing }
        guard let previousSharp = sharpSince, time - previousSharp >= 0.15, time - previousSharp <= 0.5 else {
            sharpSince = time
            return .holding
        }
        fired = true
        return .capture
    }
}

struct FrameDetail {
    let sharpness: Double
    let brightness: Double

    /// Variance of the Laplacian at a fixed analysis resolution; input is 8-bit luma.
    static func measure(_ pixels: [UInt8], width: Int, height: Int) -> Self {
        guard width > 2, height > 2, pixels.count == width * height else {
            return Self(sharpness: 0, brightness: 0)
        }
        var sum = 0.0, squared = 0.0, count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let value = Double(Int(pixels[i - 1]) + Int(pixels[i + 1]) + Int(pixels[i - width]) + Int(pixels[i + width]) - 4 * Int(pixels[i]))
                sum += value; squared += value * value; count += 1
            }
        }
        return Self(sharpness: max(0, squared / count - pow(sum / count, 2)),
                    brightness: pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count) / 255)
    }
}
