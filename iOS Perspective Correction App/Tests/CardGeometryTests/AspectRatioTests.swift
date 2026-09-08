import Foundation
import Testing
@testable import CardGeometry

private func calibration(_ orientation: Int = 1) -> CameraCalibration {
    CameraCalibration(focalX: 3300, focalY: 3250, centerX: 2100, centerY: 1400, width: 4000, height: 3000, orientation: orientation)
}

private func projected(_ ratio: Double, orientation: Int = 1, tilted: Bool = true) -> [CardPoint] {
    let k = calibration(orientation)
    let pitch = tilted ? 0.35 : 0, yaw = tilted ? -0.4 : 0, roll = tilted ? 0.17 : 0
    let corners = [CardPoint(x: 0, y: 0), CardPoint(x: ratio, y: 0), CardPoint(x: ratio, y: 1), CardPoint(x: 0, y: 1)]
    return CardGeometry.ordered(corners.map { p in
        let x = p.x - ratio / 2, y = p.y - 0.5
        let y1 = y * cos(pitch), z1 = y * sin(pitch)
        let x2 = x * cos(yaw) + z1 * sin(yaw), z2 = -x * sin(yaw) + z1 * cos(yaw)
        let x3 = x2 * cos(roll) - y1 * sin(roll), y3 = x2 * sin(roll) + y1 * cos(roll)
        let u = (k.focalX * x3 / (z2 + 4) + k.centerX) / k.width
        let v = (k.focalY * y3 / (z2 + 4) + k.centerY) / k.height
        let display: CardPoint
        switch orientation {
        case 1: display = CardPoint(x: u, y: v)
        case 2: display = CardPoint(x: 1 - u, y: v)
        case 3: display = CardPoint(x: 1 - u, y: 1 - v)
        case 4: display = CardPoint(x: u, y: 1 - v)
        case 5: display = CardPoint(x: v, y: u)
        case 6: display = CardPoint(x: 1 - v, y: u)
        case 7: display = CardPoint(x: 1 - v, y: 1 - u)
        default: display = CardPoint(x: v, y: 1 - u)
        }
        // The processing pipeline normalizes EXIF and downsizes photos.
        return CardPoint(x: display.x * (orientation >= 5 ? 1125 : 1500), y: display.y * (orientation >= 5 ? 1500 : 1125))
    })
}

@Test(arguments: [0.55, 1.0, 1.4, 2.2])
func recoversNaturalProportions(ratio: Double) throws {
    let estimate = try #require(AspectRatioEstimator.estimate(corners: projected(ratio), calibration: calibration(), imageWidth: 1500, imageHeight: 1125))
    #expect(abs(estimate.widthOverHeight - ratio) < 1e-8)
}

@Test(arguments: Array(1...8))
func calibrationFollowsEXIFAndResize(orientation: Int) throws {
    let ratio = 0.65
    let estimate = try #require(AspectRatioEstimator.estimate(corners: projected(ratio, orientation: orientation), calibration: calibration(orientation),
                imageWidth: orientation >= 5 ? 1125 : 1500, imageHeight: orientation >= 5 ? 1500 : 1125))
    #expect(abs(estimate.widthOverHeight - (orientation >= 5 ? 1 / ratio : ratio)) < 1e-8)
}

@Test func frontalRectangleNeedsNoVanishingPointGuess() throws {
    let result = try #require(AspectRatioEstimator.estimate(corners: projected(0.7, tilted: false), calibration: calibration(), imageWidth: 1500, imageHeight: 1125))
    #expect(abs(result.widthOverHeight - 0.7) < 1e-8)
}

@Test func toleratesPixelNoise() throws {
    var points = projected(0.6)
    points[0].x += 0.75; points[2].y -= 0.75
    let result = try #require(AspectRatioEstimator.estimate(corners: points, calibration: calibration(), imageWidth: 1500, imageHeight: 1125))
    #expect(abs(result.widthOverHeight - 0.6) < 0.015)
}

@Test func rejectsNonRectangularAndInvalidCalibration() {
    let rhombus = [CardPoint(x: 100, y: 100), CardPoint(x: 600, y: 100), CardPoint(x: 850, y: 533), CardPoint(x: 350, y: 533)]
    #expect(AspectRatioEstimator.estimate(corners: rhombus, calibration: calibration(), imageWidth: 1500, imageHeight: 1125) == nil)
    let invalid = CameraCalibration(focalX: 0, focalY: 1000, centerX: 500, centerY: 500, width: 1000, height: 1000, orientation: 1)
    #expect(AspectRatioEstimator.estimate(corners: projected(0.7), calibration: invalid, imageWidth: 1500, imageHeight: 1125) == nil)
    #expect(AspectRatioEstimator.estimate(corners: [], calibration: calibration(), imageWidth: 1500, imageHeight: 1125) == nil)
}
