import Foundation
import Testing
@testable import CardGeometry

private func polygonMask(_ width: Int, _ height: Int, _ points: [CardPoint]) -> [UInt8] {
    var mask = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            var inside = false
            for i in points.indices {
                let a = points[i], b = points[(i + points.count - 1) % points.count]
                if (a.y > Double(y)) != (b.y > Double(y)) && Double(x) < (b.x - a.x) * (Double(y) - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
            }
            mask[y * width + x] = inside ? 1 : 0
        }
    }
    return mask
}

private func roundedMask(width: Int = 250, height: Int = 250, angle: Double = 0, holes: Bool = false) -> ([UInt8], [CardPoint]) {
    let cx = Double(width) / 2, cy = Double(height) / 2
    let w = 116.0, h = 164.0, radius = 13.0
    let corners = [CardPoint(x: -w/2, y: -h/2), CardPoint(x: w/2, y: -h/2), CardPoint(x: w/2, y: h/2), CardPoint(x: -w/2, y: h/2)].map {
        CardPoint(x: cx + $0.x * cos(angle) - $0.y * sin(angle), y: cy + $0.x * sin(angle) + $0.y * cos(angle))
    }
    var mask = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            let dx = Double(x) - cx, dy = Double(y) - cy
            let lx = dx * cos(angle) + dy * sin(angle), ly = -dx * sin(angle) + dy * cos(angle)
            let nx = max(-w/2 + radius, min(lx, w/2 - radius))
            let ny = max(-h/2 + radius, min(ly, h/2 - radius))
            if hypot(lx - nx, ly - ny) <= radius { mask[y * width + x] = 1 }
            if holes && abs(lx) < 35 && abs(ly) < 60 && Int(ly + 60) % 10 < 2 { mask[y * width + x] = 0 }
        }
    }
    return (mask, corners)
}

private func expectNear(_ actual: [CardPoint], _ expected: [CardPoint], tolerance: Double = 3) {
    #expect(actual.count == 4)
    for p in expected { #expect(actual.map { $0.distance(to: p) }.min()! <= tolerance) }
}

@Test(arguments: [0.0, Double.pi / 12, Double.pi / 4 - 0.02])
func roundedCorners(angle: Double) throws {
    let (mask, corners) = roundedMask(angle: angle)
    let detection = try CardGeometry.detect(mask: mask, width: 250, height: 250)
    expectNear(detection.corners, corners)
    #expect(detection.confidence > 0.8)
}

@Test func perspective() throws {
    let corners = [CardPoint(x: 52, y: 22), CardPoint(x: 166, y: 40), CardPoint(x: 146, y: 190), CardPoint(x: 28, y: 168)]
    let result = try CardGeometry.detect(mask: polygonMask(210, 215, corners), width: 210, height: 215)
    expectNear(result.corners, corners, tolerance: 2.5)
    #expect(result.confidence > 0.8)
}

@Test func holesAndDisconnectedNoise() throws {
    var (mask, corners) = roundedMask(angle: .pi / 18, holes: true)
    for y in 5..<15 { for x in 5..<15 { mask[y * 250 + x] = 1 } }
    let result = try CardGeometry.detect(mask: mask, width: 250, height: 250)
    expectNear(result.corners, corners)
}

@Test func sourceScaling() throws {
    let (mask, corners) = roundedMask()
    let result = try CardGeometry.detect(mask: mask, width: 250, height: 250, sourceWidth: 750, sourceHeight: 1000)
    expectNear(result.corners, corners.map { CardPoint(x: $0.x * 3, y: $0.y * 4) }, tolerance: 8)
}

@Test func rejectsEmptyAndInvalidMasks() {
    #expect(throws: CardError.self) { try CardGeometry.detect(mask: [], width: 0, height: 0) }
    #expect(throws: CardError.self) { try CardGeometry.detect(mask: [0], width: 200, height: 200) }
    #expect(throws: CardError.self) { try CardGeometry.detect(mask: Array(repeating: 0, count: 40000), width: 200, height: 200) }
}

@Test func acceptsSquaresAndRejectsInvalidShapes() {
    let square = [CardPoint(x: 30, y: 30), CardPoint(x: 170, y: 30), CardPoint(x: 170, y: 170), CardPoint(x: 30, y: 170)]
    #expect(CardGeometry.valid(square)) // Square cards are valid now that proportions are configurable.
    let triangle = Array(square.prefix(3))
    #expect(throws: CardError.self) { try CardGeometry.detect(mask: polygonMask(200, 200, triangle), width: 200, height: 200) }
    #expect(!CardGeometry.valid([CardPoint(x: .nan, y: 0)]))
}
