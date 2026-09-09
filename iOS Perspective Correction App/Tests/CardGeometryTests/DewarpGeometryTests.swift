import Foundation
import Testing
@testable import CardGeometry

@Test(arguments: [0, 1, 2, 3]) func dewarpKeepsCornersAndAvoidsRotationCollapse(turns: Int) throws {
    let source = [CardPoint(x: 70, y: 30), CardPoint(x: 240, y: 80),
                  CardPoint(x: 200, y: 350), CardPoint(x: 30, y: 280)]
    let start = (0..<4).map { source[($0 - turns + 4) % 4] }
    let end = [CardPoint(x: 60, y: 10), CardPoint(x: 240, y: 10),
               CardPoint(x: 240, y: 310), CardPoint(x: 60, y: 310)]
    let unit = [CardPoint(x: 0, y: 0), CardPoint(x: 1, y: 0), CardPoint(x: 1, y: 1), CardPoint(x: 0, y: 1)]
    for step in 0...20 {
        let p = DewarpGeometry.corners(from: start, to: end, progress: Double(step) / 20)
        let m = try #require(DewarpGeometry.projection(to: p))
        for (u, expected) in zip(unit, p) {
            let z = m[6] * u.x + m[7] * u.y + 1
            #expect(abs(z) > 0.01)
            #expect(abs((m[0] * u.x + m[1] * u.y + m[2]) / z - expected.x) < 1e-7)
            #expect(abs((m[3] * u.x + m[4] * u.y + m[5]) / z - expected.y) < 1e-7)
        }
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            #expect((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) > 1000)
            if step == 0 { #expect(p[i].distance(to: start[i]) < 1e-8) }
            if step == 20 { #expect(p[i].distance(to: end[i]) < 1e-8) }
        }
    }
}
