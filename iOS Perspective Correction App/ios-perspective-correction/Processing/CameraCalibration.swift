import Foundation

/// Intrinsics for the unrotated, uncropped camera buffer, before JPEG EXIF orientation.
struct CameraCalibration: Sendable, Equatable {
    let focalX: Double
    let focalY: Double
    let centerX: Double
    let centerY: Double
    let width: Double
    let height: Double
    let orientation: Int

    var isValid: Bool {
        [focalX, focalY, centerX, centerY, width, height].allSatisfy(\.isFinite) &&
        focalX > 0 && focalY > 0 && width > 0 && height > 0 &&
        (0...width).contains(centerX) && (0...height).contains(centerY) && (1...8).contains(orientation)
    }

    /// Undo orientation and resizing before applying inverse intrinsics. No crop is assumed.
    func normalizedPoint(_ point: CardPoint, imageWidth: Double, imageHeight: Double) -> CardPoint? {
        guard isValid, imageWidth > 0, imageHeight > 0 else { return nil }
        let u = point.x / imageWidth, v = point.y / imageHeight
        let raw: CardPoint
        switch orientation {
        case 1: raw = CardPoint(x: u, y: v)
        case 2: raw = CardPoint(x: 1 - u, y: v)
        case 3: raw = CardPoint(x: 1 - u, y: 1 - v)
        case 4: raw = CardPoint(x: u, y: 1 - v)
        case 5: raw = CardPoint(x: v, y: u)
        case 6: raw = CardPoint(x: v, y: 1 - u)
        case 7: raw = CardPoint(x: 1 - v, y: 1 - u)
        case 8: raw = CardPoint(x: 1 - v, y: u)
        default: return nil
        }
        return CardPoint(x: (raw.x * width - centerX) / focalX, y: (raw.y * height - centerY) / focalY)
    }
}

struct AspectRatioEstimate: Sendable, Equatable {
    let widthOverHeight: Double
    let relativeUncertainty: Double
}

enum AspectRatioEstimator {
    /// H maps a unit square onto the four calibrated rays. Its first two columns
    /// are the physical side vectors up to a common scale, so their norm ratio is W/H.
    static func estimate(corners: [CardPoint], calibration: CameraCalibration,
                         imageWidth: Double, imageHeight: Double) -> AspectRatioEstimate? {
        guard CardGeometry.valid(corners), calibration.isValid else { return nil }
        func solve(_ points: [CardPoint]) -> (ratio: Double, orthogonality: Double)? {
            let rays = points.compactMap { calibration.normalizedPoint($0, imageWidth: imageWidth, imageHeight: imageHeight) }
            guard rays.count == 4 else { return nil }
            return ratioFromRays(rays)
        }
        guard let base = solve(corners), (0.2...5).contains(base.ratio), base.orthogonality < 0.12 else { return nil }
        // Reject unstable estimates rather than presenting false precision.
        var uncertainty = 0.0
        for i in 0..<4 {
            for offset in [CardPoint(x: -1.5, y: 0), CardPoint(x: 1.5, y: 0), CardPoint(x: 0, y: -1.5), CardPoint(x: 0, y: 1.5)] {
                var perturbed = corners
                perturbed[i].x += offset.x; perturbed[i].y += offset.y
                guard let sample = solve(perturbed) else { return nil }
                uncertainty = max(uncertainty, abs(sample.ratio / base.ratio - 1))
            }
        }
        guard uncertainty < 0.06 else { return nil }
        return AspectRatioEstimate(widthOverHeight: base.ratio, relativeUncertainty: uncertainty)
    }

    private static func ratioFromRays(_ points: [CardPoint]) -> (ratio: Double, orthogonality: Double)? {
        let square = [CardPoint(x: 0, y: 0), CardPoint(x: 1, y: 0), CardPoint(x: 1, y: 1), CardPoint(x: 0, y: 1)]
        var rows = [[Double]]()
        for i in 0..<4 {
            let u = square[i].x, v = square[i].y, x = points[i].x, y = points[i].y
            rows.append([u, v, 1, 0, 0, 0, -x * u, -x * v, x])
            rows.append([0, 0, 0, u, v, 1, -y * u, -y * v, y])
        }
        for column in 0..<8 {
            guard let pivot = (column..<8).max(by: { abs(rows[$0][column]) < abs(rows[$1][column]) }),
                  abs(rows[pivot][column]) > 1e-10 else { return nil }
            rows.swapAt(column, pivot)
            let divisor = rows[column][column]
            for j in column...8 { rows[column][j] /= divisor }
            for i in 0..<8 where i != column {
                let factor = rows[i][column]
                for j in column...8 { rows[i][j] -= factor * rows[column][j] }
            }
        }
        let h = rows.map { $0[8] }
        let a = [h[0], h[3], h[6]], b = [h[1], h[4], h[7]]
        let lengthA = sqrt(a.reduce(0) { $0 + $1 * $1 }), lengthB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        guard lengthA > 1e-8, lengthB > 1e-8 else { return nil }
        let ratio = lengthA / lengthB
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        guard ratio.isFinite else { return nil }
        return (ratio, abs(dot) / (lengthA * lengthB))
    }
}
